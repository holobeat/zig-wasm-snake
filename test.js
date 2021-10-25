const fs = require('fs')
const m = new WebAssembly.Module(fs.readFileSync('main.wasm'))

const env = {
  inc(x) { return x+1 }
}

const i = new WebAssembly.Instance(m, {env})

console.log(i.exports.addInc(1,2))
console.log(i.exports.mul2())
console.log(i.exports.mul2())
console.log(i.exports.mul2())