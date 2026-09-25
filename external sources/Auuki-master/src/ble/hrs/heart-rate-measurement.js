//
// Heart Rate Spec
// Heart Rate Measurement characteristic
//

function HeartRateMeasurement(args = {}) {
    const rrIntervalResolution = 1024;

    function decode(dataview) {
        const flags = dataview.getUint8(0, true);
        const heartRateValueFormat    = ((flags >> 0) & 1) === 1;
        const sensorContactStatus     = ((flags >> 1) & 1) === 1;
        const sensorContactSupported  = ((flags >> 2) & 1) === 1;
        const energyExpenditureStatus = ((flags >> 3) & 1) === 1;
        const rrIntervalPresent       = ((flags >> 4) & 1) === 1;

        let i = 1;
        let heartRate = 0;
        let energyExpenditure;
        let rrInterval;

        if(heartRateValueFormat) {
            heartRate = dataview.getUint16(i, true);
            i += 2;
        } else {
            heartRate = dataview.getUint8(i, true);
            i += 1;
        }

        if(energyExpenditureStatus) {
            energyExpenditure = dataview.getUint16(i, true);
            i += 2;
        }

        if(rrIntervalPresent) {
            rrInterval = [];
            while(i <= dataview.byteLength - 2) {
                rrInterval.push(
                    dataview.getUint16(i, true) / rrIntervalResolution
                );
                i += 2;
            }
        }

        return {
            sensorContactSupported, // Bool
            sensorContactStatus, // Bool
            heartRate, // Int
            energyExpenditure, // Int?
            rrInterval, // [Float]?
        };
    }

    return Object.freeze({
        rrIntervalResolution,
        decode,
    });
}

const heartRateMeasurement = HeartRateMeasurement();

export {
    HeartRateMeasurement,
    heartRateMeasurement
};

