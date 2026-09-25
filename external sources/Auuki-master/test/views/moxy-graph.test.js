/**
 * @jest-environment jsdom
 */

import { JSDOM } from 'jsdom';

import { first, last, xf } from '../../src/functions.js';
import { MoxyGraph } from '../../src/views/moxy-graph.js';

describe('Moxy Graph View', () => {
});

describe('Fill - Shift - Enlarge - Fill - Shift', () => {

    global.console = {
        log: jest.fn(),
        error: console.error,
        warn: console.warn,
    };

    const moxy = new MoxyGraph();
    moxy.width = 8;

    const power = [
        // path until shift 1
         0, 100, // 1s
         1, 110, // 2s
         2, 120, // 3s
         3, 130, // 4s
         4, 140, // 5s
         5, 150, // 6s
         6, 160, // 7s
         7, 170, // 8s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power1 = [
        // path after shift 1
         0, 110, // 2s
         1, 120, // 3s
         2, 130, // 4s
         3, 140, // 5s
         4, 150, // 6s
         5, 160, // 7s
         6, 170, // 8s
         7, 180, // 9s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power2 = [
        // path after shift 2
        0, 120, // 3s
        1, 130, // 4s
        2, 140, // 5s
        3, 150, // 6s
        4, 160, // 7s
        5, 170, // 8s
        6, 180, // 9s
        7, 190, // 10s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power3 = [
        // path after window enlarge 1, until shift 3
         0, 120, // 3s
         1, 130, // 4s
         2, 140, // 5s
         3, 150, // 6s
         4, 160, // 7s
         5, 170, // 8s
         6, 180, // 9s
         7, 190, // 10s
         8, 200, // 11s
         9, 210, // 12s
        10, 220, // 13s
        11, 230, // 14s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power4 = [
        // path after window enlarge 1 after shift 3
         0, 130, // 4s
         1, 140, // 5s
         2, 150, // 6s
         3, 160, // 7s
         4, 170, // 8s
         5, 180, // 9s
         6, 190, // 10s
         7, 200, // 11s
         8, 210, // 12s
         9, 220, // 13s
        10, 230, // 14s
        11, 240, // 15s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    test('init', () => {
        expect(moxy.step).toBe(1);
        expect(moxy.x).toBe(0);
        expect(moxy.path.power).toStrictEqual([]);
    });

    test(' 1s', () => {
        moxy.handlers.power(100);
        moxy.onElapsed();

        expect(moxy.x).toBe(1);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 2));
    });

    test(' 2s', () => {
        moxy.handlers.power(110);
        moxy.onElapsed();

        expect(moxy.x).toBe(2);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 4));
    });

    test(' 3s', () => {
        moxy.handlers.power(120);
        moxy.onElapsed();

        expect(moxy.x).toBe(3);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 6));
    });

    test(' 4s', () => {
        moxy.handlers.power(130);
        moxy.onElapsed();

        expect(moxy.x).toBe(4);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 8));
    });


    test(' 5s', () => {
        moxy.handlers.power(140);
        moxy.onElapsed();

        expect(moxy.x).toBe(5);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 10));
    });

    test(' 6s', () => {
        moxy.handlers.power(150);
        moxy.onElapsed();

        expect(moxy.x).toBe(6);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 12));
    });

    test(' 7s', () => {
        moxy.handlers.power(160);
        moxy.onElapsed();

        expect(moxy.x).toBe(7);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 14));
    });

    test(' 8s end', () => {
        moxy.handlers.power(170);
        moxy.onElapsed();

        expect(moxy.x).toBe(8);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 16));
    });

    // hit window end

    test(' 9s shift', () => {
        // shift 1
        moxy.handlers.power(180);
        moxy.onElapsed();

        expect(moxy.x).toBe(8);
        expect(moxy.path.power).toStrictEqual(power1.slice(0, 16));
    });

    test('10s shift', () => {
        // shift 2
        moxy.handlers.power(190);
        moxy.onElapsed();

        expect(moxy.x).toBe(8);
        expect(moxy.path.power).toStrictEqual(power2.slice(0, 16));
    });

    // enlarge window
    test('11s enlarge', () => {
        // enlarge 1
        moxy.width = 12;
        moxy.handlers.power(200);
        moxy.onElapsed();

        expect(moxy.x).toBe(9);
        expect(moxy.path.power).toStrictEqual(power3.slice(0, 18));
    });

    test('12s', () => {
        moxy.handlers.power(210);
        moxy.onElapsed();

        expect(moxy.x).toBe(10);
        expect(moxy.path.power).toStrictEqual(power3.slice(0, 20));
    });

    test('13s', () => {
        moxy.handlers.power(220);
        moxy.onElapsed();

        expect(moxy.x).toBe(11);
        expect(moxy.path.power).toStrictEqual(power3.slice(0, 22));
    });

    test('14s end', () => {
        moxy.handlers.power(230);
        moxy.onElapsed();

        expect(moxy.x).toBe(12);
        expect(moxy.path.power).toStrictEqual(power3.slice(0, 24));
    });

    test('15s shift', () => {
        moxy.handlers.power(240);
        moxy.onElapsed();

        expect(moxy.x).toBe(12);
        expect(moxy.path.power).toStrictEqual(power4.slice(0, 24));
    });
});

describe('Fill - Shift - Shrink - Fill - Shift', () => {

    const moxy = new MoxyGraph();
    moxy.width = 12;

    const power = [
        // path until shift 1
         0, 100, // 1s
         1, 110, // 2s
         2, 120, // 3s
         3, 130, // 4s
         4, 140, // 5s
         5, 150, // 6s
         6, 160, // 7s
         7, 170, // 8s
         8, 180, // 9s
         9, 190, // 10s
         10, 200, // 11s
        11, 210, // 12s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power1 = [
        // path after shift 1
         0, 110, // 2s
         1, 120, // 3s
         2, 130, // 4s
         3, 140, // 5s
         4, 150, // 6s
         5, 160, // 7s
         6, 170, // 8s
         7, 180, // 9s
         8, 190, // 10s
         9, 200, // 11s
        10, 210, // 12s
        11, 220, // 13s
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power2 = [
        // path after shift 2
        0, 120, // 3s   , 80
        1, 130, // 4s   , 78.33333333333333
        2, 140, // 5s   , 76.66666666666667
        3, 150, // 6s   , 75
        4, 160, // 7s   , 73.33333333333333
        5, 170, // 8s   , 71.66666666666667
        6, 180, // 9s   , 70
        7, 190, // 10s  , 68.33333333333334
        8, 200, // 11s  , 66.66666666666667
        9, 210, // 12s  , 65
        10, 220, // 13s , 63.333333333333336
        11, 230, // 14s , 61.666666666666664
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power3 = [
        // path after window shrink 1, after shift 3
        // 0, 120, // 3s
        // 1, 130, // 4s
        // 2, 140, // 5s
        // 3, 150, // 6s // shrink
        // 0, 160, // 7s // shift
        0, 170, // 8s  , 71.66666666666667
        1, 180, // 9s  , 70
        2, 190, // 10s , 68.33333333333334
        3, 200, // 11s , 66.66666666666667
        4, 210, // 12s , 65

        5, 220, // 13s , 63.333333333333336
        6, 230, // 14s , 61.666666666666664
        7, 240, // 15s , 60
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    const power4 = [
        // path after window shrink 1 after shift 4
    ].map((x, i) => i % 2 !== 0 ? moxy.translateY('power', x) : x);

    test('init', () => {
        expect(moxy.step).toBe(1);
        expect(moxy.x).toBe(0);
        expect(moxy.path.power).toStrictEqual([]);
    });

    test(' 1s', () => {
        moxy.handlers.power(100);
        moxy.onElapsed();

        expect(moxy.x).toBe(1);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 2));
    });

    test(' 2s', () => {
        moxy.handlers.power(110);
        moxy.onElapsed();

        expect(moxy.x).toBe(2);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 4));
    });

    test(' 3s', () => {
        moxy.handlers.power(120);
        moxy.onElapsed();

        expect(moxy.x).toBe(3);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 6));
    });

    test(' 4s', () => {
        moxy.handlers.power(130);
        moxy.onElapsed();

        expect(moxy.x).toBe(4);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 8));
    });


    test(' 5s', () => {
        moxy.handlers.power(140);
        moxy.onElapsed();

        expect(moxy.x).toBe(5);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 10));
    });

    test(' 6s', () => {
        moxy.handlers.power(150);
        moxy.onElapsed();

        expect(moxy.x).toBe(6);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 12));
    });

    test(' 7s', () => {
        moxy.handlers.power(160);
        moxy.onElapsed();

        expect(moxy.x).toBe(7);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 14));
    });

    test(' 8s', () => {
        moxy.handlers.power(170);
        moxy.onElapsed();

        expect(moxy.x).toBe(8);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 16));
    });

    test(' 9s', () => {
        moxy.handlers.power(180);
        moxy.onElapsed();

        expect(moxy.x).toBe(9);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 18));
    });

    test('10s', () => {
        moxy.handlers.power(190);
        moxy.onElapsed();

        expect(moxy.x).toBe(10);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 20));
    });

    test('11s', () => {
        moxy.handlers.power(200);
        moxy.onElapsed();

        expect(moxy.x).toBe(11);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 22));
    });

    test('12s end', () => {
        moxy.handlers.power(210);
        moxy.onElapsed();

        expect(moxy.x).toBe(12);
        expect(moxy.path.power).toStrictEqual(power.slice(0, 24));
    });

    // hit window end

    test('13s shift', () => {
        moxy.handlers.power(220);
        moxy.onElapsed();

        expect(moxy.x).toBe(12);
        expect(moxy.path.power).toStrictEqual(power1.slice(0, 24));
    });

    test('14s shift', () => {
        moxy.handlers.power(230);
        moxy.onElapsed();

        expect(moxy.x).toBe(12);
        expect(moxy.path.power).toStrictEqual(power2.slice(0, 24));
    });

    // shrink window

    test('15s shrink - shift', () => {
        moxy.width = 8;
        moxy.handlers.power(240);
        moxy.onElapsed();

        expect(moxy.x).toBe(8);
        // expect(moxy.path.power).toStrictEqual(power3.slice(0, 16));
        expect(moxy.path.power[0]).toStrictEqual(power3[0]);
        expect(moxy.path.power[1]).toStrictEqual(power3[1]);
        expect(moxy.path.power[2]).toStrictEqual(power3[2]);
        expect(moxy.path.power[3]).toStrictEqual(power3[3]);
        expect(moxy.path.power[5]).toStrictEqual(power3[5]);
        expect(moxy.path.power[7]).toStrictEqual(power3[7]);
        expect(moxy.path.power[9]).toStrictEqual(power3[9]);
        expect(moxy.path.power[11]).toStrictEqual(power3[11]);
        expect(moxy.path.power[13]).toStrictEqual(power3[13]);
        expect(moxy.path.power[15]).toStrictEqual(power3[15]);
    });

});

