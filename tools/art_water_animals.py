#!/usr/bin/env python3
"""Four animals of the water's edge in the established miniature 3D pixel renderer (numpy, same as rabbits, corvids, owls):
  heron      Reiher: 64x64, feet (32, 54). 2 builds (blue-grey, silver). idle 0:4, hunch 4:8, wade 8:16, strike 16:22, catch 22:26, preen 26:30, fly 30:38, takeoff 38:44, land 44:50
  frog       Frosch: 32x32, feet (16, 24). 2 builds (moss green, teal with a violet back). idle 0:4, croak 4:8, hop 8:14, swim 14:20
  kingfisher Eisvogel: 32x32, feet (16, 24). 1 build. perch 0:4, look 4:8, dive 8:14, fly 14:20, catch 20:24
  duck       Ente: 40x40, feet (20, 31). 3 builds (drake, hen, duckling). float 0:4, paddle 4:10, dabble 10:16, preen 16:20, fly 20:28, takeoff 28:34
Every row of a sheet is build * 8 + facing (E SE S SW W NW N NE like all wildlife); no emission, the animals are world-lit.
`python3 tools/art_water_animals.py [--preview-only]` writes assets/wildlife/{heron,frog,kingfisher,duck}.png and docs/img/water_animals.png"""
import math
import sys
from pathlib import Path

import numpy as np

import art_hero3d as art
from gen_art import CLEAR, hexc
from world_data import save_png

ROOT = Path(__file__).resolve().parent.parent
art.SS, art.SCALE = 3, 1.
art.DECAL_WEIGHT = {3: 3.0, 4: 2.6, 5: 1.6}
art.ink_color = lambda mat: hexc('1c1a28')


def rx(a):
    return art.rot_x(a)


def bez(p0, p1, p2, n=14):
    p0, p1, p2 = (np.array(p, float) for p in (p0, p1, p2))
    return [(1 - t) ** 2 * p0 + 2 * t * (1 - t) * p1 + t * t * p2 for t in (i / n for i in range(n + 1))]


def chain(m, pts, r0, r1, mat):
    for i in range(len(pts) - 1):
        a = i / (len(pts) - 1)
        m.limb(pts[i], pts[i + 1], r0 + (r1 - r0) * a, r0 + (r1 - r0) * (a + 1 / (len(pts) - 1)), mat, step=.6)


def ramps(*rs):
    if len(rs) == 1:
        rs = rs[0]
    art.RAMPS = [[hexc(c) for c in r] for r in rs]


def lerp(a, b, k):
    return np.array(a, float) * (1 - k) + np.array(b, float) * k


def ease(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


# ====================================================================== heron
def heron(v, kind, t):
    ramps(['2c3a4c', '4a6078', '7890a6', 'b4c4d0'] if v == 0 else ['5a6a7c', '8090a2', 'aebac6', 'd8e0e8'],
          ['8a98a8', 'b4c0cc', 'dce4ea', 'f8fcfc'],
          ['0c0e18', '1c2030', '2c3044', '404658'],
          ['a0661c', 'd4902c', 'f0b848', 'ffe08a'],
          ['d8d4a4', 'f2eec0', 'fff8d8', 'ffffff'],
          ['505e70', '74849a', '9eb0c0', 'd0dce6'],
          ['5c4a24', '8c7438', 'b89c54', 'e0cc88'])  # 6: the dull olive-ochre of legs and feet
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    flying = kind in ('fly', 'takeoff', 'land')
    by = 25.0 + (0.25 * b if kind in ('idle', 'hunch') else 0.0)
    s_pose, hunch, turn, fish = 0.0, 0.0, 0.0, False
    if kind == 'hunch':
        hunch = 1.0
    if kind == 'strike':  # waits, then the neck shoots forward and down and comes back
        s_pose = ease(t * 2.2) if t < .45 else 1.0 - ease((t - .45) * 1.8)
        hunch = 0.4 * (1 - s_pose)
    if kind == 'catch':
        hunch = .2
        fish = True
    if kind == 'preen':
        turn = 1.0
        hunch = .5
    pitch = .24 - .1 * hunch - .42 * s_pose  # nose up when standing tall, down in the strike
    fl = 0.0  # 0 legs hanging, 1 trailing straight behind
    if flying:
        hunch = 1.0
        by = 27.0
        if kind == 'fly':
            pitch, fl = .05 + .04 * math.sin(p), 1.0
        elif kind == 'takeoff':
            pitch, fl = .62 - .5 * ease(t), ease(t * 1.15)
        else:  # land: nose up, legs swing forward and down to meet the ground
            pitch, fl = .5 - .3 * ease(t), 1.0 - ease(t * 1.2)
    R = rx(-pitch)
    c = np.array([0, by, 0])

    def T(x, y, z):  # body-local to model space: the whole torso pitches about the middle
        return c + R @ np.array([x, y - by, z], float)
    # torso: a long grey back, a white breast with shaggy hanging plumes, the black shoulder patch, silvery scapulars
    m.ell(T(0, by, -.5), (3.3, 4.1, 8.6), 0, R=R)
    m.ell(T(0, by + .6, 4.6), (2.9, 3.7, 4.2), 1, R=R)
    m.ell(T(0, by - 1.2, -8.6), (1.6, 1.1, 2.4), 0, R=R)
    for j in range(5):  # breast plumes: loose lanceolate feathers hanging from the base of the neck
        x = (j - 2) * .75
        m.limb(T(x, by + 1.6, 6.4), T(x * 1.2, by - 3.6 - (j % 2) * 1.2, 6.0 - abs(j - 2) * .3), .62, .15, 1 if j % 2 == 0 else 5, step=.6)
    for side in (-1, 1):
        for j in range(2):  # long silvery scapulars lying along the back
            m.limb(T(side * (1.5 + j * .5), by + 3.4 - j * .3, 0.2 - j), T(side * (1.2 + j * .3), by + .6 - j * .5, -11.0 - j * 1.2), .62, .12, 1, step=.7)
    # head and neck first (the neck is thin and S-shaped, the head small and flat with a dagger bill)
    shoulder = T(0, by + 2.0, 5.4)
    head_tall = np.array([0, by + 19.0, 7.8])
    head_hunch = np.array([0, by + 6.2, 8.2])
    head_strike = np.array([0, by - 14.0, 21.0])
    head = lerp(lerp(head_tall, head_hunch, hunch), head_strike, s_pose)
    if turn:
        head = head + np.array([2.6, -1.0, -9.0])
    if kind == 'wade':
        head = head + np.array([0, .4 * math.sin(p * 2), .5 * math.sin(p)])
    ctrl = lerp(lerp(np.array([0, by + 14, 1.0]), np.array([0, by + 8.5, -.5]), hunch), np.array([0, by + 6, 11]), s_pose)
    if turn:
        ctrl = ctrl + np.array([-1, 0, -4])
    if flying:  # in flight the neck is drawn in: a thick S, the head just ahead of the shoulders
        head = T(0, by + 3.4, 9.6)
        ctrl = T(0, by + 7.6, 4.6)
    neck = bez(shoulder, ctrl, head - np.array([0, 0, 1.4]) if not turn else head, n=14)
    chain(m, neck, 1.75 if not flying else 2.0, 1.05, 0)
    for i in range(2, 13, 2):  # the dark dotted streak down the front of the throat
        m.ell(neck[i] + np.array([0, -.1, 1.0 if not turn else -1.0]), (.34, .55, .34), 5 if v == 1 else 2)
    m.ell(head, (1.6, 1.5, 2.4), 1)  # white crown and cheeks
    m.ell(head + np.array([0, -.5, .8]), (1.15, .85, 1.6), 1)
    for side in (-1, 1):  # the black band from the eye to the long crest plumes
        m.ell(head + np.array([side * 1.25, .6, .2]), (.34, .5, 1.7), 2)
        m.limb(head + np.array([side * .5, 1.0, -1.2]), head + np.array([side * .7, -.2, -8.6]), .55, .1, 2, step=.6)
        m.limb(head + np.array([side * .3, .8, -1.0]), head + np.array([side * .2, -1.3, -7.0]), .4, .1, 2, step=.6)
        m.ell(head + np.array([side * 1.35, .55, 1.3]), (.3, .35, .35), 4)
        m.ell(head + np.array([side * 1.4, .6, 1.5]), (.14, .14, .14), 2)
    strike_open = kind == 'strike' and s_pose > .5
    bill_end = head + (np.array([0, -.9, 9.8]) if not strike_open else np.array([0, -4.5, 8.8]))
    m.limb(head + np.array([0, -.4, 1.6]), bill_end, .85, .2, 3, step=.5)
    m.limb(head + np.array([0, -.1, 1.8]), bill_end - (bill_end - head) * .12 + np.array([0, .12, 0]), .35, .16, 6, step=.5)  # the darker ridge
    if fish:
        m.limb(bill_end - np.array([0, .3, 1.5]), bill_end + np.array([0, -4.5, 2.5]), .75, .55, 5, step=.5)
    # wings
    for side in (-1, 1):
        if not flying:
            m.ell(T(side * 3.2, by + .4, -1.0), (1.2, 3.6, 7.4), 0, R=R @ rx(-.06))
            m.ell(T(side * 3.5, by + 1.4, 2.8), (.8, 1.2, 1.8), 2, R=R)  # black shoulder patch
            for j in range(4):  # dark flight feathers laid over the tail, tips crossing
                m.limb(T(side * (3.0 - j * .15), by - 1.4 + j * .25, -4.0 - j * .8), T(side * (2.2 - j * .6), by - 3.4 + j * .2, -12.6 - j * 1.1), .8, .22, 2 if j % 2 == 0 else 5, step=.7)
            continue
        ph = (t if kind == 'fly' else (t * .75 if kind == 'takeoff' else .5 + t * .45)) * math.tau
        amp = 1.0 if kind == 'fly' else (1.25 if kind == 'takeoff' else .9)
        a_s = .18 + .5 * amp * math.sin(ph)
        a_w = .08 + .72 * amp * math.sin(ph - .55)
        a_t = -.12 + .95 * amp * math.sin(ph - 1.05)
        if kind == 'land':
            a_s, a_w, a_t = a_s + .5, a_w + .6, a_t + .4
        L1, L2, L3 = 9.4, 9.2, 6.4
        S = T(side * 2.8, by + 2.2, 1.2)
        E = S + R @ np.array([side * L1 * math.cos(a_s), L1 * math.sin(a_s), 1.6])
        W = E + R @ np.array([side * L2 * math.cos(a_w), L2 * math.sin(a_w), -1.4])
        P = W + R @ np.array([side * L3 * math.cos(a_t), L3 * math.sin(a_t), -3.0])
        m.limb(S, E, 2.1, 1.7, 0, step=1.0)
        m.limb(E, W, 1.7, 1.2, 0, step=1.0)
        for j in range(5):  # coverts over the arm
            q = S * (1 - j / 4.0) + W * (j / 4.0)
            m.ell(q + R @ np.array([0, -.4, -1.8]), (1.5, .6, 2.4), 5 if j % 2 else 0, R=R)
        for j in range(7):  # secondaries: broad, trailing, a little drooped
            q = S * (1 - j / 6.0) + W * (j / 6.0) + R @ np.array([0, -.3, -1.6])
            m.limb(q, q + R @ np.array([side * (.5 + .12 * j), -.5 - .3 * math.sin(ph - .4 - j * .1), -(9.4 - .55 * j)]), 1.3, .4, 5, step=1.0)
        for j in range(8):  # primaries: fingered, dark tips, spread along the hand
            u = j / 7.0
            q = W * (1 - (.3 + .7 * u)) + P * (.3 + .7 * u)
            m.limb(q, q + R @ np.array([side * (1.2 + 2.6 * u), -.2 + .5 * math.sin(a_t), -(8.2 - 1.8 * u)]), 1.05, .28, 2 if j > 1 else 5, step=1.0)
    # legs: long, thin, thick-ankled, with a white thigh; hanging when standing, trailing in flight
    for side in (-1, 1):
        swing = lift = 0.0
        if kind == 'wade':
            ph = p + (math.pi if side > 0 else 0.0)
            swing = 3.5 * math.cos(ph)
            lift = max(0.0, -math.sin(ph)) * 6.0
        hip = np.array([side * 1.6, by - 3.0, -1.2])
        knee = np.array([side * 1.8, 12.0 + lift * .7 + (by - 25.0), .8 + swing * .5 + lift * .12])
        foot = np.array([side * 1.9, .8 + lift + (by - 25.0), .6 + swing])
        if fl > 0:
            hb = np.array([side * 1.2, by - 3.4, -6.4])
            knee = lerp(knee, np.array([side * 1.0, by - 5.4, -14.5]), fl)
            foot = lerp(foot, np.array([side * 1.0, by - 6.4 - 1.4 * (1 - fl), -23.0]), fl)
            hip = lerp(hip, hb, fl)
        m.ell(hip + np.array([0, -1.2, 0]), (1.1, 2.3, 1.3), 1)  # feathered thigh
        m.limb(hip + np.array([0, -2.0, 0]), knee, .72, .58, 6, step=.6)
        m.limb(knee, foot, .6, .45, 6, step=.6)
        m.ell(knee, (.75, .75, .75), 6)
        toe_dir = (1, 0, -1) if fl > .5 else (-1, 0, 1)
        for toe in (-1, 0, 1):
            tip = foot + np.array([toe * .9, -.2 if fl < .5 else 0, (2.6 + (.8 if toe == 0 else 0)) * (1 if fl < .5 else -1)])
            m.limb(foot, tip, .34, .14, 6, step=.5)
        m.limb(foot, foot + np.array([0, -.1, -1.8 if fl < .5 else 1.8]), .3, .14, 6, step=.5)
    return m


# ====================================================================== frog
def frog(v, kind, t):
    ramps([['1a3a22', '2e6a34', '58a04a', '9ad06c'] if v == 0 else ['143a46', '2a6a74', '48a0a0', '90d4c8'],
           ['a8b868', 'd4dc90', 'ecf0b8', 'fffbe0'], ['10201a', '1c3624', '2a4a34', '3a5e44'],
           ['c89a18', 'e8c030', 'f6dc58', 'fff0a0'], ['0a0c10', '0a0c10', '181c20', '303438'],
           ['5a3a7a', '8a62b0', 'b896d8', 'dccaf0'] if v == 1 else ['3a5a2a', '5a8a3e', '88b858', 'b4de84']])
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    by, pitch, lift = 2.9, 0.0, 0.0
    sac = 0.5
    hind = 0.0  # 0 folded, 1 stretched out behind
    if kind == 'idle':
        by += .12 * b
        sac = .5 + .15 * b
    if kind == 'croak':
        sac = .6 + 1.5 * ease(math.sin(t * math.pi))
        by += .1 * b
    if kind == 'hop':
        k = t
        lift = 6.0 * math.sin(k * math.pi)
        pitch = .5 * math.sin(k * math.pi)
        hind = ease(k * 2) if k < .5 else 1.0 - ease(k * 2 - 1)
        by = 3.2 + lift
    if kind == 'swim':
        by = 1.8
        hind = .5 + .5 * math.sin(p)
        pitch = .08
    R = rx(-pitch)
    m.ell((0, by, 0), (3.2, 2.5, 4.4), 0, R=R)
    m.ell((0, by - .9, .4), (2.6, 1.4, 3.6), 1, R=R)
    for k in range(5):  # darker spots on the back
        m.ell((((k * 7) % 5 - 2) * .9, by + 2.0, -2.0 + k * 1.0), (.8, .3, .7), 5 if v == 1 else 2, R=R)
    m.ell((0, by + 1.2, 3.8), (2.7, 2.1, 2.6), 0, R=R)
    m.ell((0, by - .1, 5.2), (1.8, 1.1, 1.3), 0, R=R)  # snout
    for side in (-1, 1):
        m.ell((side * 1.7, by + 3.0, 4.2), (1.1, 1.1, 1.1), 0, R=R)
        m.ell((side * 1.85, by + 3.2, 4.8), (.8, .8, .5), 3)
        m.ell((side * 1.9, by + 3.3, 5.1), (.5, .5, .3), 4)
        # hind legs: folded Z when sitting, stretched back when hopping or kicking
        hip = np.array([side * 2.6, by - .2, -2.4])
        knee = lerp([side * 4.4, by + .5, -.4], [side * 3.0, by - .6 - (0 if kind == 'hop' else .0), -5.5], hind)
        foot = lerp([side * 3.6, .5 + lift * .3, 2.4], [side * 2.0, by - 1.8, -9.5 if kind != 'swim' else -8.0 + side * math.sin(p) * 1.5], hind)
        m.limb(hip, knee, 1.25, .8, 0, step=.5)
        m.limb(knee, foot, .8, .55, 0, step=.5)
        for toe in (-1, 0, 1):
            m.limb(foot, foot + np.array([toe * .9, -.1, 2.2 if hind < .5 else -2.2]), .3, .18, 1, step=.4)
        fore = np.array([side * 1.7, by - .8, 3.2])
        m.limb(fore, np.array([side * 1.9, max(.4, by - 2.3 + lift * .2), 4.4]), .6, .45, 0, step=.4)
    m.ell((0, by - 1.6, 4.9), (1.3 * sac + .3, .9 * sac + .1, 1.2 * sac + .2), 1, R=R)  # the throat sac
    return m


# ====================================================================== kingfisher
def kingfisher(v, kind, t):
    ramps([['0e5a78', '1a8ea0', '38c0c0', '88e8e0'], ['b84a14', 'e07a22', 'f4a24a', 'ffd08a'], ['10202c', '1c3444', '2c4a5c', '44687c'],
           ['f4f0e0', 'fffaf0', 'ffffff', 'ffffff'], ['0a0c10', '0a0c10', '181c20', '303438'], ['5a6a78', '8898a6', 'b4c4d0', 'dce8f0']])
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    flying = kind in ('fly',)
    dive = kind == 'dive'
    k = t
    pitch = 0.0
    by = 5.4 + (.1 * b if kind in ('perch', 'look') else 0)
    turn = 0.0
    fish = kind == 'catch'
    if kind == 'look':
        turn = .9 * math.sin(p)
    if dive:  # hover, then plunge head first
        pitch = -ease(k * 1.5) * 1.35
        by = 9.0 - 3.5 * ease(k)
    if flying:
        by = 8.0
        pitch = -.05
    R = rx(-pitch)
    c = np.array([0, by, 0])

    def T(x, y, z):
        return c + R @ np.array([x, y - by, z], float)
    m.ell(T(0, by, 0), (2.3, 2.7, 3.5), 0, R=R)
    m.ell(T(0, by - .7, 1.5), (1.9, 2.1, 2.0), 1, R=R)  # orange breast
    m.ell(T(0, by + 1.0, -1.2), (1.5, .9, 2.4), 0, R=R)
    for j in range(3):
        m.ell(T(0, by - 1.0, -3.2 - j * .5), (.9 - j * .15, .6, .9), 2, R=R)
    hz = 2.9
    hy = by + 2.6
    m.ell(T(turn * .6, hy, hz), (2.0, 2.0, 2.3), 0, R=R)
    m.ell(T(0, hy - 1.5, hz + .6), (1.3, .8, 1.4), 3, R=R)  # white throat
    m.ell(T(turn * .6 + 1.7, hy - .2, hz + .8), (.45, .5, .55), 1, R=R)  # the orange cheek patch
    m.ell(T(-turn * .6 - 1.7, hy - .2, hz + .8), (.45, .5, .55), 1, R=R)
    m.limb(T(turn * .6, hy - .3, hz + 1.4), T(turn * .8, hy - .4, hz + 6.6), .95, .22, 2, step=.4)  # the dagger bill
    for sd in (-1, 1):
        m.ell(T(sd * 1.5 + turn * .6, hy + .5, hz + 1.0), (.42, .45, .42), 4)
        m.ell(T(sd * 1.5 + turn * .6, hy + .7, hz + 1.3), (.17, .17, .17), 3)
    if fish:
        m.limb(T(0, hy - .6, hz + 5.2), T(0, hy - 2.8, hz + 8.0), .7, .5, 5, step=.4)
    for sd in (-1, 1):
        if flying or dive:
            ph = t if flying else .2 * math.sin(k * 8)
            flap = math.sin(ph * math.tau * (1 if flying else 4))
            reach = 7.5 if flying else 5.0
            rise = flap * 4.2 if flying else 1.0
            sh = T(sd * 1.6, by + 1, 0)
            tip = T(sd * reach, by + 1.2 + rise, -1.8)
            m.limb(sh, tip, 1.1, .4, 0, step=.6)
            for j in range(4):
                f = j / 3.0
                pos = sh * (1 - f) + tip * f
                m.limb(pos, pos + R @ np.array([sd * .8, -.3, -3.0]), .55, .2, 2, step=.5)
        else:
            m.ell(T(sd * 2.1, by + .1, -.9), (.75, 2.0, 2.9), 0, R=R @ rx(-.12))
            m.ell(T(sd * 2.15, by + .6, -2.2), (.5, 1.0, 1.8), 2, R=R)
            m.limb(T(sd * 1.1, by - 2.0, .4), (sd * 1.1, .4, .4), .4, .34, 1, step=.4)  # red feet on the perch
            for toe in (-1, 0, 1):
                m.limb((sd * 1.1, .4, .4), (sd * 1.1 + toe * .5, .2, 1.4), .2, .13, 1, step=.4)
    return m


# ====================================================================== duck
def duck(v, kind, t):
    """v 0 drake (grey back, green head, white collar, chestnut breast, black curled stern), 1 hen (mottled browns), 2 duckling (yellow, dark eye stripe)."""
    young = v == 2
    ramps([['5c6068', '82868e', 'aaaeb6', 'd2d6dc'], ['5a4028', '84603c', 'b08a58', 'd8b886'], ['b08a1c', 'd4aa30', 'ecc84c', 'fff0a0']][v],  # 0 body
          [['5a2c22', '82463a', 'aa664e', 'd08c6a'], ['785a38', 'a68050', 'cca874', 'ead0a0'], ['f0d868', 'fbe898', 'fff6c0', 'ffffff']][v],  # 1 breast
          [['0a0a12', '181a24', '262a38', '3a4050'], ['2e2016', '48341f', '644a2c', '82643c'], ['6a4a22', '8a6430', 'b08440', 'd4a860']][v],  # 2 stern, markings
          [['8a8a1c', 'b8b42c', 'dcd648', 'f4f08c'], ['9c5a22', 'c47e34', 'e0a050', 'f8c880'], ['d87a1a', 'f09a30', 'ffbc58', 'ffe090']][v],  # 3 bill
          ['0a0c10', '0a0c10', '181c20', '303438'],  # 4 eye
          ['1e2e8a', '3650c8', '6a86ec', 'aec4ff'],  # 5 speculum
          [['0c3426', '186040', '2a9060', '58c486'], ['5a4028', '84603c', 'b08a58', 'd8b886'], ['f0d868', 'fbe898', 'fff6c0', 'ffffff']][v],  # 6 head
          ['a8b0b8', 'd0d6dc', 'eef0f4', 'ffffff'],  # 7 white
          ['b8581a', 'dc7c2a', 'f4a040', 'ffcc80'])  # 8 feet
    q = .74 if young else 1.22
    hq = 1.32 if young else 1.0  # ducklings: big round head
    m = art.Model()
    p = t * math.tau
    b = math.sin(p)
    flying = kind in ('fly', 'takeoff')
    by = 3.2 * q + (.2 * b * q if kind == 'float' else 0)
    pitch = 0.0
    head_down = 0.0
    if kind == 'dabble':  # tail up, head under
        ph = ease(math.sin(t * math.pi) * 1.4)
        pitch = .9 * ph
        head_down = ph
    if kind == 'paddle':
        by += .15 * math.sin(p * 2) * q
    if flying:
        by = 7.0 * q
        pitch = -.12 if kind == 'fly' else -.3 + .2 * t
    R = rx(-pitch)
    c = np.array([0, by, 0])

    def T(x, y, z):
        return c + R @ (np.array([x, y - by, z], float) * q)

    def E(pos, r, mat, RR=R):
        m.ell(pos, tuple(x * q for x in r), mat, R=RR)
    # boat-shaped body, chest, and a pointed stern
    E(T(0, by, -.6), (3.6, 2.9, 6.2), 0)
    E(T(0, by + .2, 2.4), (3.1, 2.6, 3.4), 1)
    E(T(0, by - .6, 4.0), (2.4, 1.7, 2.0), 1)
    E(T(0, by + .9, -5.6), (1.5, 1.2, 2.4), 2, R @ rx(-.5))
    if v == 0:
        m.limb(T(0, by + 1.6, -6.4), T(0, by + 3.6, -8.2), .7 * q, .25 * q, 2, step=.5)  # the curled drake feather
        m.limb(T(0, by + 3.6, -8.2), T(0, by + 3.9, -6.6), .35 * q, .2 * q, 2, step=.5)
    elif young:  # the dark down stripe along the back and a pale face
        E(T(0, by + 2.3, -1.2), (1.1, .32, 4.4), 2)
        for sd in (-1, 1):
            E(T(sd * 1.7, by + 1.4, -3.4), (.5, .4, .8), 2)
    elif v == 1:
        for k in range(9):  # mottled back
            E(T(((k * 5) % 7 - 3) * .85, by + 2.2 - abs(((k * 5) % 7 - 3)) * .25, -4.0 + k * .75), (.7, .25, .6), 2)
    hz, hy = 4.4, by + 3.6 - 5.6 * head_down
    if kind == 'dabble':
        hz = 4.4 + 3.0 * head_down
    if flying:  # the neck stretched straight out
        hz, hy = 7.4, by + 2.2
    neck = bez(T(0, by + 1.6, 2.8), T(0, by + 4.6 - 3 * head_down - (2.2 if flying else 0), 3.8), T(0, hy, hz), n=8)
    chain(m, neck, 1.55 * q, 1.2 * q, 6 if v == 0 else 1 if not young else 6)
    if v == 0:
        m.ell(neck[1] + np.array([0, 0, .3 * q]), (1.55 * q, .55 * q, 1.55 * q), 7)  # the white collar
    head = T(0, hy + .2, hz + .4)
    m.ell(head, (1.9 * q * hq, 1.85 * q * hq, 2.4 * q * hq), 6)
    m.ell(head + np.array([0, .6 * q, -.2 * q]), (1.5 * q * hq, 1.0 * q * hq, 1.6 * q * hq), 6)
    bill = T(0, hy - .6, hz + 2.9)
    m.ell(bill, (1.05 * q, .5 * q, 1.7 * q), 3)  # the flat bill with its darker nail
    m.ell(bill + np.array([0, -.05, 1.3 * q]), (.8 * q, .36 * q, .6 * q), 2 if v != 0 else 4)
    if v == 1:
        m.ell(T(0, hy - .6, hz + 2.5), (1.1 * q, .5 * q, 1.0 * q), 2)  # the dark saddle on a hen's bill
    for sd in (-1, 1):
        m.ell(T(sd * 1.7, hy + .7, hz + 1.1), (.46 * q * hq, .48 * q * hq, .42 * q), 4)
        m.ell(T(sd * 1.78, hy + .85, hz + 1.3), (.18 * q * hq, .18 * q * hq, .16 * q), 7)  # a glint
        if v != 0:  # the dark stripe through the eye
            m.ell(T(sd * 1.6, hy + .3, hz + .8), (.3 * q, .32 * q, 1.7 * q), 2)
        else:  # the white cheek line of a drake
            m.ell(T(sd * 1.75, hy - .2, hz + .8), (.18 * q, .22 * q, 1.4 * q), 7)
    for sd in (-1, 1):
        if flying:
            ph = (t if kind == 'fly' else t * .9) * math.tau
            a1 = .2 + .75 * math.sin(ph)
            a2 = .1 + .85 * math.sin(ph - .6)
            a3 = -.1 + .95 * math.sin(ph - 1.1)
            S = T(sd * 2.8, by + 1.6, .8)
            Ek = S + R @ np.array([sd * 5.2 * q * math.cos(a1), 5.2 * q * math.sin(a1), .4])
            Wr = Ek + R @ np.array([sd * 5.0 * q * math.cos(a2), 5.0 * q * math.sin(a2), -1.2 * q])
            Pt = Wr + R @ np.array([sd * 3.4 * q * math.cos(a3), 3.4 * q * math.sin(a3), -1.8 * q])
            m.limb(S, Ek, 1.5 * q, 1.2 * q, 0, step=.8)
            m.limb(Ek, Wr, 1.2 * q, .9 * q, 0, step=.8)
            for j in range(5):  # secondaries with the blue speculum and white bars
                f = j / 4.0
                pos = S * (1 - f) + Wr * f
                m.limb(pos, pos + R @ np.array([sd * .5 * q, -.4, -(5.0 - .3 * j) * q]), 1.1 * q, .35 * q, 5 if j == 2 else (7 if j in (1, 3) else 0), step=.7)
            for j in range(5):
                f = j / 4.0
                pos = Wr * (1 - f * .8) + Pt * (f * .8)
                m.limb(pos, pos + R @ np.array([sd * (.8 + f * 1.4) * q, -.2, -(4.6 - .6 * f) * q]), .8 * q, .2 * q, 2 if j > 1 else 0, step=.7)
        else:  # folded wing: grey-brown, the blue speculum with white borders near the back, tips crossing over the stern
            E(T(sd * 3.3, by + .5, -.8), (.95, 2.3, 4.8), 0, R @ rx(-.06))
            E(T(sd * 3.55, by + .1, -3.4), (.55, .55, 1.0), 5)
            E(T(sd * 3.5, by + .1, -4.5), (.5, .5, .5), 7)
            m.limb(T(sd * 3.0, by + .8, -4.6), T(sd * .6, by + 1.4, -8.4), .8 * q, .2 * q, 2, step=.6)
    if kind in ('paddle', 'float', 'dabble') and not flying:  # orange feet paddling just under the body
        for sd in (-1, 1):
            m.ell(T(sd * 1.7, -1.2 + (math.sin(p * 2 + sd) * .5 if kind == 'paddle' else 0), -1.2 + (math.cos(p * 2 + sd) * 1.2 if kind == 'paddle' else 0)), (.9 * q, .2 * q, 1.5 * q), 8)
    elif flying:
        for sd in (-1, 1):
            m.ell(T(sd * 1.4, by - 2.0, -6.0), (.8 * q, .2 * q, 1.5 * q), 8)
    return m


# ====================================================================== sheets
SPECIES = {
    'heron': dict(size=64, ground=54, builds=2, fn=heron, blocks=[('idle', 0, 4), ('hunch', 4, 4), ('wade', 8, 8), ('strike', 16, 6), ('catch', 22, 4), ('preen', 26, 4), ('fly', 30, 8), ('takeoff', 38, 6), ('land', 44, 6)]),
    'frog': dict(size=32, ground=24, builds=2, fn=frog, blocks=[('idle', 0, 4), ('croak', 4, 4), ('hop', 8, 6), ('swim', 14, 6)]),
    'kingfisher': dict(size=32, ground=24, builds=1, fn=kingfisher, blocks=[('perch', 0, 4), ('look', 4, 4), ('dive', 8, 6), ('fly', 14, 6), ('catch', 20, 4)]),
    'duck': dict(size=40, ground=31, builds=3, fn=duck, blocks=[('float', 0, 4), ('paddle', 4, 6), ('dabble', 10, 6), ('preen', 16, 4), ('fly', 20, 8), ('takeoff', 28, 6)]),
}


def render(name, v, d, col):
    spec = SPECIES[name]
    art.FW = art.FH = spec['size']
    art.GROUND_ROW = float(spec['ground'])
    kind, start, n = next(b for b in spec['blocks'] if b[1] <= col < b[1] + b[2])
    kind_in = {'perch': 'perch', 'preen': 'preen'}.get(kind, kind)
    if name == 'kingfisher' and kind == 'perch':
        kind_in = 'perch'
    t = (col - start) / n
    model = spec['fn'](v, kind_in if not (name == 'heron' and kind == 'wade') else 'wade', t)
    depth, code = art.render(model.transform(math.pi / 2 - d * math.pi / 4, 0))
    return np.array([[CLEAR if c[3] < 255 else c for c in row] for row in art.to_pixels(depth, code)], dtype=np.uint8)


def main():
    preview_only = '--preview-only' in sys.argv
    previews = []
    for name, spec in SPECIES.items():
        s = spec['size']
        cols = sum(b[2] for b in spec['blocks'])
        sheet = np.zeros((spec['builds'] * 8 * s, cols * s, 4), np.uint8)
        picks = [(d, start + n // 2) for kind, start, n in spec['blocks'] for d in (0, 2)]
        pv = np.zeros((spec['builds'] * s, len(picks) * s, 4), np.uint8)
        for v in range(spec['builds']):
            for d in range(8):
                if preview_only and not any(d == pd for pd, _ in picks):
                    continue
                for col in range(cols):
                    if preview_only and (d, col) not in picks:
                        continue
                    px = render(name, v, d, col)
                    sheet[(v * 8 + d) * s:(v * 8 + d + 1) * s, col * s:(col + 1) * s] = px
                    if (d, col) in picks:
                        x = picks.index((d, col)) * s
                        pv[v * s:(v + 1) * s, x:x + s] = px
            print(name, 'build', v + 1, '/', spec['builds'], flush=True)
        if not preview_only:
            save_png(ROOT / 'assets/wildlife' / (name + '.png'), sheet)
        previews.append(pv)
    width = max(p.shape[1] for p in previews)
    out = np.zeros((sum(p.shape[0] for p in previews), width, 4), np.uint8)
    y = 0
    for pv in previews:
        out[y:y + pv.shape[0], :pv.shape[1]] = pv
        y += pv.shape[0]
    save_png(ROOT / 'docs/img/water_animals.png', out)


if __name__ == '__main__':
    main()
