var wInst;
var mem;
var start, previousTimeStamp;
var delta = 0;
var aborted = false;
var fields = [];
var domScore, domPages, domGameArena, domMessage;
var keyMap = {
    ArrowUp: 'w',
    ArrowDown: 's',
    ArrowLeft: 'a',
    ArrowRight: 'd'
};

const resetDelta = () => {
    delta = 0;
    start = performance.now();
};

const consoleLog = (ptr, len) => {
    console.log((new TextDecoder()).decode(new Uint8Array(mem.buffer, ptr, len)));
};

const paintField = (index, r, g, b) => {
    fields[index].style.backgroundColor = 'rgb(' + r + ',' + g + ',' + b + ')';
};

const showScore = (score) => domScore.innerHTML = score;

const showPage = (page) => {
    for (var i = 0; i < domPages.length; i++) {
        domPages[i].style.display = i === page ? 'block' : 'none';
    }
};

const showMessage = (ptr, len) => {
    let msg = (new TextDecoder()).decode(new Uint8Array(mem.buffer, ptr, len));
    domMessage.innerHTML = msg;
    domMessage.style.display = 'block';
}

const hideMessage = () => domMessage.style.display = 'none';

const drawGameArena = (arenaSize) => {
    const gameArenaPadding = 1;
    const fieldSize = 15;
    const fieldBorderSize = 2;
    const fieldBorderRadius = 3;
    const fullFieldSize = fieldSize + fieldBorderSize;

    // clear content
    domGameArena.innerHTML = '';
    fields = [];

    domGameArena.style.width = arenaSize * fullFieldSize + fieldBorderSize + 'px';
    domGameArena.style.height = arenaSize * fullFieldSize + fieldBorderSize + 'px';
    domGameArena.style.padding = gameArenaPadding + 'px';

    for (var y = 0; y < arenaSize; y++) {
        for (var x = 0; x < arenaSize; x++) {
            var field = document.createElement('div');
            field.className = 'field';
            field.style.width = fieldSize + 'px';
            field.style.height = fieldSize + 'px';
            field.style.borderRadius = fieldBorderRadius + 'px';
            field.style.left = (x * fullFieldSize + gameArenaPadding) + 'px';
            field.style.top = (y * fullFieldSize + gameArenaPadding) + 'px';
            fields.push(field);
            domGameArena.appendChild(field);
        }
    }
};

const wasmBrowserInstantiate = async (wasmUrl, importObject) => {

    if (!importObject) {
        importObject = {
            env: {
                abort: () => aborted = true,
                resetDelta: resetDelta,
                consoleLog: consoleLog,
                paintField: paintField,
                drawGameArena: drawGameArena,
                showScore: showScore,
                showPage: showPage,
                showMessage: showMessage,
                hideMessage: hideMessage,
                getRandomInt: (max) => Math.floor(Math.random() * max),
            }
        };
    }

    if (WebAssembly.instantiateStreaming) {
        return await WebAssembly.instantiateStreaming(fetch(wasmUrl), importObject);
    } else {
        return await (async () => {
            const buffer = await fetch(wasmUrl).then(response => response.arrayBuffer());
            return (await WebAssembly.instantiate(buffer, importObject));
        })();
    }
};

const step = (timestamp) => {
    if (aborted) return;
    if (start === undefined) start = timestamp;
    delta = timestamp - start;
    wInst.exports.update(delta);
    previousTimeStamp = timestamp;
    window.requestAnimationFrame(step);
};

const remapKey = (key) => {
    if(keyMap.hasOwnProperty(key)) return keyMap[key];
    return key;
}

const runWasmApp = async () => {
    const source = await wasmBrowserInstantiate("./main.wasm");

    wInst = source.instance;
    mem = wInst.exports.memory;

    const exports = wInst.exports;

    document.body.onkeydown = (ev) => {
        let key = remapKey(ev.key);
        exports.onKeyDown(key.charCodeAt(0));
    };

    domScore = document.getElementById('score');
    domPages = [
        document.getElementById('page-intro'),
        document.getElementById('page-game'),
    ];
    domGameArena = document.getElementById('game-arena');
    domMessage = document.getElementById('message');

    exports.init(30);

    // start update loop
    window.requestAnimationFrame(step);

};
