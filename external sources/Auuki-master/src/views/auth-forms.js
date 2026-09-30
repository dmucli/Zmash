import { xf, empty, } from '../functions.js';
import { models } from '../models/models.js';

// TODO: This needs refactoring to something more general with
// declarative configuration. Something that will work for all tabs and switches.
class AuthForms extends HTMLElement {
    constructor() {
        super();
    }
    connectedCallback() {
        const self = this;
        this.abortController = new AbortController();
        this.signal = { signal: self.abortController.signal };

        this.el = {
            // each subset is exclusive or with css class .active
            //
            // tabs
            // passkey, password
            // forms
            // passkey -> login, register -> profile
            // password -> login, register, forgot, reset -> profile
            // error
            // switch: {
            //     $passkey: document.querySelector('#passkey--tab--switch'),
            //     $password: document.querySelector('#password--tab--switch'),
            // },
            // tab: {
            //     $passkey:  document.querySelector('#passkey--forms'),
            //     $password: document.querySelector('#password--forms'),
            // },
            password: {
                $register: self.querySelector('#register--form'),
                $login: self.querySelector('#login--form'),
                $forgot: self.querySelector('#forgot--form'),
                $reset: self.querySelector('#reset--form'),
                $profile: document.querySelector('#profile'),
            },
            // passkey: {
            //     $register: self.querySelector('#passkey--register--form'),
            //     $login: self.querySelector('#passkey--login--form'),
            //     $profile: document.querySelector('#profile'),
            // },
            $logout: document.querySelector('#logout--button'),
            $error: document.querySelector('#auth-error--section'),
            $pwds: document.querySelectorAll('input[type="password"]'),
        };

        this.subForm('password', '$login', 'login');
        this.subForm('password', '$register', 'register');
        this.subForm('password', '$forgot', 'forgot');
        this.subForm('password', '$reset', 'reset');

        this.el.$logout.addEventListener('pointerup', (e) => {
            models.api.auth.logout();
        });

        this.$forgotMsg = document.querySelector('#forgot--msg'),

        xf.sub('action:auth', self.onAction.bind(this));
    }
    disconnectedCallback() {
        this.abortController.abort();
    }
    subForm(group, form, method) {
        const $form = this.el[group][form];

        $form.addEventListener('submit', async (e) => {
            e.preventDefault();
            const formData = new FormData($form);
            const cfTurnstileResponse = window.turnstile.getResponse();
            if(cfTurnstileResponse === undefined) { return; }
            formData.append('cf-turnstile-response', cfTurnstileResponse);
            const data = Object.fromEntries(formData);

            await models.api.auth[method]({data,});
            $form.reset();

            // TODO:
            // refresh turnstile
            if(method === 'register' ||
               method === 'forgot' ||
               method === 'reset') {
                models.api.auth.resetTurnstile();
            }

        }, this.signal);
    }
    onAction(action) {
        const self = this;
        console.log(action);

        // TODO: figure out a condition
        // models.api.auth.loadTurnstile();

        if(action === ':password') {
            this.switch('$password', this.el.tab);
            this.switch('$password', this.el.switch);
            return;
        }
        // if(action === ':passkey') {
        //     // TODO: fix when webauthn is ready
        //     // this.switch('$passkey', this.el.tab);
        //     // this.switch('$passkey', this.el.switch);
        //     return;
        // }
        if(action === ':password:login') {
            this.switch('$login', this.el.password);
            return;
        }
        if(action === ':password:register') {
            this.switch('$register', this.el.password);
            return;
        }
        if(action === ':password:forgot') {
            this.switch('$forgot', this.el.password);
            return;
        }
        if(action === ':password:reset') {
            this.switch('$reset', this.el.password);
            return;
        }
        if(action === ':password:profile') {
            this.switch('$profile', this.el.password);
            return;
        }
        if(action === ':password:logout') {
            this.switch('$login', this.el.password);
            return;
        }
        // if(action === ':passkey:login') {
        //     this.switch('$login', this.el.passkey);
        //     return;
        // }
        // if(action === ':passkey:register') {
        //     this.switch('$register', this.el.passkey);
        //     return;
        // }
        if(action === ':forgot:loading') {
            console.log(`:view :action:auth :forgot:loading`);
            this.$forgotMsg.textContent = "Sending reset request ...";
            this.$forgotMsg.classList.remove('success');
            this.$forgotMsg.classList.remove('error');
            this.$forgotMsg.classList.add('loading');
        }
        if(action === ':forgot:success') {
            console.log(`:view :action:auth :forgot:success`);
            this.$forgotMsg.textContent = "An email with a password reset link has been sent to your email!";
            this.$forgotMsg.classList.remove('loading');
            this.$forgotMsg.classList.remove('error');
            this.$forgotMsg.classList.add('success');
        }
        if(action === ':forgot:fail') {
            console.log(`:view :action:auth :forgot:fail`);
            this.$forgotMsg.textContent = "Something went wrong while sending a password reset email!";
            this.$forgotMsg.classList.remove('loading');
            this.$forgotMsg.classList.remove('success');
            this.$forgotMsg.classList.add('error');
        }
        if(action === ':error') {
            this.error('Wrong credentials or Authentication error');
            return;
        }
        if(action === ':no-api') {
            this.switch('', this.el.tab);
            this.switch('', this.el.password);
            this.switch('', this.el.passkey);
            this.error('No internet connection or the API service is currently offline.');
            return;
        }
    }
    switch(target, elements) {
        this.el.$error.classList.remove('active');

        // prevent potential content flash
        // by first removing and only after that adding .active
        // if there is no target element this is not an error,
        // it means all content should be 'non-active'
        for(let prop in elements) {
            if(!(target === prop)) {
                elements[prop].classList.remove('active');
            }
        }
        if(target) {
            elements[target].classList.add('active');
        }
    }
    error(msg = '') {
        if(msg !== '') {
            this.el.$error.textContent = msg;
        }
        this.el.$error.classList.add('active');
        this.el.$pwds.forEach(($el) => $el.value = '');
    }
}

customElements.define('auth-forms', AuthForms);

