const http = require('http');
const net = require('net');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const root = path.resolve(__dirname, '../mobile/build/web');
const port = Number(process.env.NGROK_PORT || 5001);
const types = {'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png','.svg':'image/svg+xml','.css':'text/css','.woff2':'font/woff2'};
const server = http.createServer((req,res) => {
  let pathname;
  try {pathname = decodeURIComponent(req.url.split('?')[0]);} catch {res.writeHead(400); return res.end();}
  if (pathname === '/assets/.env') {
    res.writeHead(200, {'Content-Type':'text/plain','Cache-Control':'no-store'});
    return res.end(`API_BASE_URL=${req.headers['x-forwarded-proto'] || 'http'}://${req.headers.host}\n`);
  }
  if (pathname.split('/').some(p => p.startsWith('.'))) {res.writeHead(404); return res.end();}
  if (/^\/(api|media)\//.test(pathname)) {
    const upstream = http.request({hostname:'127.0.0.1',port:8000,path:req.url,method:req.method,headers:req.headers}, response => {
      res.writeHead(response.statusCode,response.headers); response.pipe(res);
    });
    upstream.on('error', () => {res.writeHead(502);res.end();}); req.pipe(upstream); return;
  }
  const file = path.join(root, pathname === '/' ? 'index.html' : pathname);
  fs.stat(file, (err,stat) => {
    if (err || !stat.isFile()) {res.writeHead(404);return res.end();}
    const headers = {'Content-Type':types[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store'};
    const compress = /gzip/.test(req.headers['accept-encoding'] || '') && /\.(js|json|wasm|html|css|svg)$/.test(file);
    if (compress) {headers['Content-Encoding']='gzip';headers.Vary='Accept-Encoding';}
    res.writeHead(200,headers);
    if (req.method === 'HEAD') return res.end();
    const stream = fs.createReadStream(file);
    stream.on('error',()=>res.destroy());
    if (compress) stream.pipe(zlib.createGzip()).pipe(res); else stream.pipe(res);
  });
});
server.on('upgrade',(req,socket,head) => {
  if (!req.url.startsWith('/ws/')) return socket.destroy();
  const upstream = net.connect(8000,'127.0.0.1',()=>{
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`+Object.entries(req.headers).map(([k,v])=>`${k}: ${v}\r\n`).join('')+'\r\n');
    if(head.length) upstream.write(head);
    socket.pipe(upstream).pipe(socket);
  });
  upstream.on('error',()=>socket.destroy()); socket.on('error',()=>upstream.destroy()); socket.on('close',()=>upstream.destroy());
});
server.on('error', error => { console.error(error.message); process.exit(1); });
server.listen(port,'127.0.0.1',()=>console.log(`Music Room release serving on port ${port}`));
