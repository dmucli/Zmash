/**
 * @jest-environment jsdom
 */

import { isoDate, } from '../src/utils.js';

// nyc        utc        hel
//
// 24 16:00   24 21:00   24 23:00
// 24 17:00   24 22:00   25 00:00
//
// 24 18:00   25 23:00   25 01:00
// 24 19:00   25 00:00   25 02:00
// 24 20:00   25 01:00   25 03:00
//
// 24 23:00   25 04:00   25 06:00
// 25 00:00   25 05:00   25 07:00
// 25 01:00   25 06:00   25 08:00

describe('isoDate', () => {
    // TODO: make the test machine env timezone independent

    describe('hel', () => {
        describe('local = true', () => {
            test('utc 24 21:00 - hel 24 23:00 -> 24', () => {
                const localDate = new Date('2025-02-24T23:00:00');
                expect(isoDate(localDate)).toBe('2025-02-24');
            });

            test('utc 24 22:00 - hel 25 00:00 -> 25', () => {
                const localDate = new Date('2025-02-25T00:00:00');
                expect(isoDate(localDate)).toBe('2025-02-25');
            });

            test('utc 24 23:00 - hel 25 01:00 -> 25', () => {
                const localDate = new Date('2025-02-25T00:00:00');
                expect(isoDate(localDate)).toBe('2025-02-25');
            });

            test('utc 25 00:00 - hel 25 02:00 -> 25', () => {
                const localDate = new Date('2025-02-25T02:00:00');
                expect(isoDate(localDate)).toBe('2025-02-25');
            });

            test('utc 25 01:00 - hel 25 03:00 -> 25', () => {
                const localDate = new Date('2025-02-25T02:00:00');
                expect(isoDate(localDate)).toBe('2025-02-25');
            });
        });

        describe('local = false', () => {
            test('utc 24 21:00 - hel 24 23:00 -> 24', () => {
                const localDate = new Date('2025-02-24T23:00:00');
                expect(isoDate(localDate, false)).toBe('2025-02-24');
            });

            test('utc 24 22:00 - hel 25 00:00 -> 24', () => {
                const localDate = new Date('2025-02-25T00:00:00');
                expect(isoDate(localDate, false)).toBe('2025-02-24');
            });

            test('utc 25 00:00 - hel 25 02:00 -> 25', () => {
                const localDate = new Date('2025-02-25T02:00:00');
                expect(isoDate(localDate, false)).toBe('2025-02-25');
            });

            test('utc 25 01:00 - hel 25 03:00 -> 25', () => {
                const localDate = new Date('2025-02-25T02:00:00');
                expect(isoDate(localDate, false)).toBe('2025-02-25');
            });
        });
    });
});

