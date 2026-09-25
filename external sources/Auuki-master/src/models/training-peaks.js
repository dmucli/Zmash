import { xf, once, } from '../functions.js';
import { OAuthService, DialogMsg, stateParam, } from './enums.js';
import config from './config.js';

function TrainingPeaks(args = {}) {
    const serviceName = OAuthService.trainingPeaks;
    const api_uri = config.get().API_URI;
    const pwa_uri = config.get().PWA_URI;
    let training_peaks_client_id = config.get().TRAINING_PEAKS_CLIENT_ID;

    const update = function() {
        training_peaks_client_id = config.get().TRAINING_PEAKS_CLIENT_ID;
    };

    // Step D
    async function connect() {
        const scope = 'file:write workouts:wod';
        const state = stateParam.encode(serviceName);
        stateParam.store(state);

        const url =
              'https://oauth.sandbox.trainingpeaks.com/OAuth/Authorize' +
              '?' +
              new URLSearchParams({
                  response_type: 'code',
                  client_id: training_peaks_client_id,
                  scope,
                  redirect_uri: pwa_uri,
                  state,
              }).toString();
        console.log(url);
        console.log(training_peaks_client_id);
        console.log(scope);
        console.log(pwa_uri);
        window.location.replace(url);
    }

    async function disconnect() {
        try {
            const serviceResponse = await fetch(
                'https://oauth.sandbox.trainingpeaks.com/oauth/deauthorize',
                {method: 'POST',}
            );
            console.log(`:oauth :trainingPeaks :disconnect`);
            const serviceBody = await serviceResponse.text();

            const apiResponse = await fetch(
                api_uri+`/api/trainingpeaks/deauthorize`,
                {method: 'POST', credentials: 'include',},
            );

            const apiBody = await apiResponse.text();

            xf.dispatch(`services`, {trainingPeaks: false});
        } catch (e) {
            console.log(`:trainingPeaks :deauthorize :error `, e);
        }
    }

    // Step 3
    async function paramsHandler(args = {}) {
        const state = args.state ?? '';
        const code = args.code ?? '';
        const scope = args.scope ?? '';

        const url = `${api_uri}/api/trainingpeaks/oauth/code` +
              '?' +
              new URLSearchParams({
                  state: state,
                  code: code,
                  scope: scope,
              })
              .toString();

        try {
            const response = await fetch(url, {
                method: 'POST',
                credentials: 'include',
            });

            const result = await response.text();
            console.log(`:oauth :trainingPeaks :connnect`);
            xf.dispatch(`services`, {trainingPeaks: true});
            console.log(result);
            clearParams();
        } catch (e) {
            console.log(`:trainingPeaks :oauth :code :error `, e);
        }
    }

    function clearParams() {
        window.history.pushState({}, document.title, window.location.pathname);
    }

    async function uploadWorkout(record) {
        const blob = record.blob;
        const workoutName = record.summary.name;
        const url = `${api_uri}/api/trainingpeaks/upload`;

        const formData = new FormData();
        formData.append('file', blob);

        try {
            const response = await fetch(url, {
                method: 'POST',
                credentials: 'include',
                body: formData,
            });

            if(response.ok) {
                return ':success';
            } else {
                if(response.status === 403) {
                    console.log(`:api :no-auth`);
                    xf.dispatch('action:auth', ':password:login');

                    xf.dispatch('ui:modal:error:open', DialogMsg.noAuth);
                }
                return ':fail';
            }
        } catch(e) {
            console.log(`:trainingPeaks :upload :error `, e);
            return ':fail';
        }
    }

    return Object.freeze({
        connect,
        disconnect,
        paramsHandler,
        uploadWorkout,
        update,
    });
}

const trainingPeaks = TrainingPeaks();

export default trainingPeaks;

