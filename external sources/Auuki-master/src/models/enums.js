import { uuid } from '../storage/uuid.js';

const DialogMsg = {
    noAuth: ':no-auth',
};

const OAuthService = {
    strava: 'strava',
    intervals: 'intervals',
    trainingPeaks: 'trainingPeaks',
};

function StateParam() {
    function encode(name) {
        const param = name+'_'+uuid();
        return param;
    }
    function decode(param) {
        const parts = param.split('_');

        return {
            service: parts[0] ?? '',
            id: parts[1] ?? '',
        };
    }

    function store() {
    }

    function restore() {
    }

    return Object.freeze({
        encode,
        decode,
        store,
        restore,
    });
}

const stateParam = StateParam();

export {
    OAuthService,
    DialogMsg,
    StateParam,
    stateParam,
}

