// Userland alternative for the deprecated punycode module

function encode(input) {
    return input.split('').map(char => {
        const code = char.charCodeAt(0);
        return code > 127 ? 'xn--' + code.toString(16) : char;
    }).join('');
}

function decode(input) {
    return input.split('xn--').map(part => {
        if (part.length === 0) return '';
        const code = parseInt(part, 16);
        return String.fromCharCode(code);
    }).join('');
}

module.exports = {
    encode,
    decode
};
