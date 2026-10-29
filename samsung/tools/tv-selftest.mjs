// Runs the self test in the app on the TV through its Web Inspector (Chrome DevTools Protocol) and prints the
// app's log lines. tv.ps1 -SelfTest starts the app with the inspector and forwards the port first.
//   node tools/tv-selftest.mjs <port> [expression]
// With an expression, it evaluates that instead and prints the result. Exits 0 when every case passes.
const port = process.argv[2];
const expression = process.argv[3];
if (!port) {
  console.error('usage: node tools/tv-selftest.mjs <inspector port> [expression]');
  process.exit(2);
}

const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const ws = new WebSocket(targets[0].webSocketDebuggerUrl);
const pending = new Map();
let nextId = 0;

function send(method, params = {}) {
  return new Promise((resolve) => {
    const id = ++nextId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

const timeout = setTimeout(() => finish('TIMEOUT', 2), 6 * 60 * 1000);

function finish(line, code) {
  if (line) console.log(line);
  clearTimeout(timeout);
  ws.close();
  process.exit(code);
}

ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (message.id && pending.has(message.id)) {
    pending.get(message.id)(message);
    pending.delete(message.id);
  } else if (message.method === 'Runtime.consoleAPICalled') {
    const text = message.params.args.map((arg) => arg.value ?? arg.description ?? '').join(' ');
    if (!text.startsWith('YP|')) return;
    console.log(text);
    const done = text.match(/SELFTEST done: (\d+)\/(\d+)/);
    if (done) finish(null, done[1] === done[2] ? 0 : 1);
  } else if (message.method === 'Runtime.exceptionThrown') {
    const details = message.params.exceptionDetails;
    console.log('exception: ' + (details.exception?.description ?? details.text));
  }
};

ws.onopen = async () => {
  await send('Runtime.enable');
  const reply = await send('Runtime.evaluate', {
    expression: expression ?? 'SelfTest.run()',
    awaitPromise: true,
    returnByValue: true,
  });
  if (expression) {
    const result = reply.result?.exceptionDetails?.exception?.description ?? reply.result?.result?.value;
    finish(JSON.stringify(result, null, 2), 0);
  }
};
