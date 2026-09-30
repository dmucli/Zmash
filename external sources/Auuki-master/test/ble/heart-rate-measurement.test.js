import { uuids } from '../../src/ble/web-ble.js';
import { heartRateMeasurement } from '../../src/ble/hrs/heart-rate-measurement.js';

global.console = {
    log: jest.fn(),
    error: console.error,
    warn: console.warn,
};

describe('HeartRateMeasurement', () => {

    describe('HeartRate Field', () => {
        test('Uint8', () => {
            const data = new DataView(new Uint8Array([0, 81]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 81,
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });
        test('Uint16', () => {
            const data = new DataView(new Uint8Array([0b00000001, 44, 1]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 300,
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });
    });
    describe('RRInterval Field', () => {
        const resolution = heartRateMeasurement.rrIntervalResolution;

        test('1 value', () => {
            const data = new DataView(new Uint8Array([0b00010000, 67, 114, 3]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 67,
                rrInterval: [882 / resolution]
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });

        test('2 values', () => {
            const data = new DataView(new Uint8Array([0b00010000, 68, 114, 3, 138, 3]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 68,
                rrInterval: [882 / resolution, 906 / resolution]
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });

        test('3 values', () => {
            const data = new DataView(new Uint8Array([0b00010000, 103, 114, 3, 138, 3, 149, 4]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 103,
                rrInterval: [882 / resolution, 906 / resolution, 1173 / resolution]
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });

        test('and energy expenditure field present', () => {
            const data = new DataView(new Uint8Array([0b00011000, 67, 208, 7, 114, 3]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 67,
                energyExpenditure: 2000,
                rrInterval: [882 / resolution]
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });
    });
    describe('EnergyExpenditure Field', () => {
        test('energy expenditure', () => {
            const data = new DataView(new Uint8Array([0b00001000, 67, 208, 7]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 67,
                energyExpenditure: 2000,
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });

        test('and Uint16 Heart Rate', () => {
            const data = new DataView(new Uint8Array([0b00001001, 44, 1, 208, 7]).buffer);
            const expected = {
                sensorContactSupported: false,
                sensorContactStatus: false,
                heartRate: 300,
                energyExpenditure: 2000,
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });
    });
    describe('SensorContact Flag', () => {
        test('supported, no contact', () => {
            const data = new DataView(new Uint8Array([0b00000100, 67]).buffer);
            const expected = {
                sensorContactSupported: true,
                sensorContactStatus: false,
                heartRate: 67,
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });

        test('supported, contact', () => {
            const data = new DataView(new Uint8Array([0b00000110, 67]).buffer);
            const expected = {
                sensorContactSupported: true,
                sensorContactStatus: true,
                heartRate: 67,
            };
            const res = heartRateMeasurement.decode(data);
            expect(res).toEqual(expected);
        });
    });
});
