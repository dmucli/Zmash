//
// Battery Service
//

import { expect, exists, dataviewToArray, } from '../../functions.js';
import { uuids, } from '../web-ble.js';
import { Service } from '../service.js';
import { Characteristic } from '../characteristic.js';
import { batteryLevel as batteryLevelParser } from './battery-level.js';

function BAS(args = {}) {

    // config
    const onData = args.onData;
    // const onRead = args.onRead;

    // BluetoothRemoteGATTService{
    //     device: BluetoothDevice,
    //     uuid: String,
    //     isPrimary: Bool,
    // }
    const gattService = expect(
        args.service, 'BAS needs BluetoothRemoteGATTService!'
    );
    // end config

    // service
    const spec = {
        measurement: {
            uuid: uuids.batteryLevel,
            // read: {callback: onData, parser: batteryLevelParser},
            notify: {callback: onData, parser: batteryLevelParser},
        },
    };

    const service = Service({spec, service: gattService,});
    // end service

    async function readBatteryLevel() {
        const measurement = service.characteristics.measurement;

        if(!exists(measurement)) return false;

        const res = await measurement.read();
        return res;
    }

    return Object.freeze({
        ...service, // BAS will have all the public methods and properties of Service
        readBatteryLevel,
    });
}

export default BAS;
