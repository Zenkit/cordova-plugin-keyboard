var cordova = require('cordova');
var exec = require('cordova/exec');

var isNil = function (value) {
    return value === undefined || value === null;
};

var Keyboard = { isVisible: false };

window.addEventListener('keyboardDidShow', function () {
    Keyboard.isVisible = true;
});

window.addEventListener('keyboardDidHide', function () {
    Keyboard.isVisible = false;
});

Keyboard.keyboardShrinksView = function (shrink, success, failure) {
    var args = isNil(shrink) ? [] : [shrink];
    exec(success, failure, 'Keyboard', 'keyboardShrinksView', args);
};

Keyboard.hideFormAccessoryBar = function (hide, success, failure) {
    var args = isNil(hide) ? [] : [hide];
    exec(success, failure, 'Keyboard', 'hideFormAccessoryBar', args);
};

Keyboard.keyboardDisablesScrolling = function (disable, success, failure) {
    var args = isNil(disable) ? [] : [disable];
    exec(success, failure, 'Keyboard', 'keyboardDisablesScrolling', args);
};

Keyboard.show = function (success, failure) {
    exec(success, failure, 'Keyboard', 'show', []);
};

Keyboard.hide = function (success, failure) {
    exec(success, failure, 'Keyboard', 'hide', []);
};

Keyboard.setKeyboardStyle = function (style) {
    exec(null, null, 'Keyboard', 'setKeyboardStyle', [style]);
};

module.exports = Keyboard;
