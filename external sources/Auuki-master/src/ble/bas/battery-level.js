//
// Battery Service Spec
// Battery Level (characteristic)
//

import { dataviewToArray, } from '../../functions.js';

function BatteryLevel() {

    function decode(dataview) {
        const batteryLevel = dataview.getUint8(0, true); // 0-100, %

        return {
            batteryLevel,
        };
    }

    return Object.freeze({
        decode,
    });
}

const batteryLevel = BatteryLevel();

export {
    batteryLevel
}

