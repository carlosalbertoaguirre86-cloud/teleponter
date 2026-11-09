// Páginas HTML servidas por la conexión remota y el modo director.

const _sharedCss = '''
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;background:#000;color:#fff;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.w{transition:color .15s,opacity .15s}
.read{opacity:.45}
.cur{font-weight:700}
.ann{font-style:italic;color:#8e8e93}
#bar{position:fixed;left:0;right:0;bottom:0;display:flex;align-items:center;gap:10px;padding:10px 14px;background:rgba(20,20,22,.92);font-size:14px;color:#aaa}
#wave{display:flex;align-items:center;gap:2px;height:22px}
#wave i{display:block;width:3px;background:#30d158;border-radius:2px;min-height:2px}
#prog{flex:1;min-width:60px;height:4px;background:#333;border-radius:2px;overflow:hidden}
#prog div{height:100%;width:0;background:#30d158}
button{background:#2c2c2e;color:#fff;border:0;border-radius:8px;padding:8px 12px;font-size:14px}
''';

const remoteViewerHtml =
    '''<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Teleponter remoto</title><style>$_sharedCss
#wrap{position:fixed;inset:0 0 52px 0;overflow:hidden}
#text{padding:30vh 6vw 60vh;font-size:clamp(26px,6vw,64px);line-height:1.35;word-wrap:break-word;transition:transform .25s ease-out}
.mx{transform:scaleX(-1)}.my{transform:scaleY(-1)}.mxy{transform:scale(-1,-1)}
#msg{position:fixed;inset:0;display:flex;align-items:center;justify-content:center;color:#666;font-size:20px;text-align:center;padding:20px}
</style></head><body>
<div id="wrap"><div id="flip"><div id="text"></div></div></div>
<div id="msg">Esperando al teleprompter…</div>
<div id="bar"><div id="wave"></div><div id="prog"><div></div></div><span id="pg"></span>
<button id="mir">Espejo</button><button id="big">A+</button><button id="small">A−</button></div>
<script>
const q=new URLSearchParams(location.search);
let mirror=q.get('mirror')!=null?q.get('mirror')==='1':localStorage.getItem('tp_mirror')==='1';
let size=parseFloat(localStorage.getItem('tp_size')||'0');
const T=document.getElementById('text'),F=document.getElementById('flip'),W=document.getElementById('wrap');
function applyMirror(){F.className=mirror?'mx':'';localStorage.setItem('tp_mirror',mirror?'1':'0')}
function applySize(){if(size>0)T.style.fontSize=size+'px';localStorage.setItem('tp_size',size)}
applyMirror();applySize();
document.getElementById('mir').onclick=()=>{mirror=!mirror;applyMirror()};
document.getElementById('big').onclick=()=>{size=(size||parseFloat(getComputedStyle(T).fontSize))+4;applySize()};
document.getElementById('small').onclick=()=>{size=Math.max(14,(size||parseFloat(getComputedStyle(T).fontSize))-4);applySize()};
const wave=document.getElementById('wave');for(let i=0;i<24;i++)wave.appendChild(document.createElement('i'));
let key='',spans=[];
function render(s){
  document.getElementById('msg').style.display=s.isActive&&s.words.length?'none':'flex';
  const k=s.words.join(' ');
  if(k!==key){key=k;T.innerHTML='';spans=s.words.map((w,i)=>{const e=document.createElement('span');e.className='w'+(s.annotation[i]?' ann':'');e.textContent=w+' ';T.appendChild(e);return e});}
  const cur=Math.floor(s.wordPosition);
  spans.forEach((e,i)=>{e.classList.toggle('read',i<cur);e.classList.toggle('cur',i===cur);e.style.color=(i<=cur&&!s.annotation[i])?s.cueColor:''});
  const target=spans[Math.min(cur,spans.length-1)];
  if(target){const y=target.offsetTop-W.clientHeight*0.3;T.style.transform='translateY('+(-y)+'px)'}
  const bars=wave.children;s.audioLevels.forEach((l,i)=>{bars[i].style.height=Math.max(2,l*22)+'px'});
  wave.style.opacity=s.isListening?1:.25;
  document.querySelector('#prog div').style.width=(s.totalCharCount?100*s.highlightedCharCount/s.totalCharCount:0)+'%';
  document.getElementById('pg').textContent=s.countdown?('Siguiente en '+s.countdown+'…'):(s.pageCount>1?s.page+'/'+s.pageCount:'');
}
function connect(){const ws=new WebSocket('ws://'+location.host+'/ws');
  ws.onmessage=e=>{try{render(JSON.parse(e.data))}catch(x){console.error(x)}};
  ws.onclose=()=>{document.getElementById('msg').style.display='flex';document.getElementById('msg').textContent='Reconectando…';setTimeout(connect,1500)}}
connect();
</script></body></html>''';

const directorHtml =
    '''<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Teleponter · Director</title><style>$_sharedCss
body{display:flex;flex-direction:column;padding:14px 14px 70px;gap:10px;background:#111}
h1{font-size:18px;font-weight:600}
#status{font-size:13px;color:#8e8e93}
#read{background:#000;border-radius:10px;padding:12px;font-size:18px;line-height:1.5;color:#30d158;white-space:pre-wrap;max-height:30vh;overflow:auto;display:none}
textarea{font-family:inherit;flex:1;min-height:40vh;width:100%;background:#000;color:#fff;border:1px solid #333;border-radius:10px;padding:12px;font-size:18px;line-height:1.5;resize:none}
.row{display:flex;gap:8px;flex-wrap:wrap}
#go{background:#30d158;color:#000;font-weight:700}
#stop{background:#ff453a}
</style></head><body>
<h1>Modo director</h1><div id="status">Conectando…</div>
<div id="read"></div>
<textarea id="ed" placeholder="Escribe o pega el guion y pulsa Iniciar"></textarea>
<div class="row"><button id="go">▶ Iniciar</button><button id="upd">Actualizar texto</button><button id="pause">Pausa</button><button id="stop">■ Detener</button></div>
<div id="bar"><div id="wave"></div><div id="prog"><div></div></div><span id="pg"></span></div>
<script>
const token=new URLSearchParams(location.search).get('t')||'';
let ws,active=false,read=0,lastSent='';
const ed=document.getElementById('ed'),R=document.getElementById('read'),S=document.getElementById('status');
const wave=document.getElementById('wave');for(let i=0;i<24;i++)wave.appendChild(document.createElement('i'));
function send(o){if(ws&&ws.readyState===1)ws.send(JSON.stringify(o))}
document.getElementById('go').onclick=()=>{lastSent=ed.value;send({type:'setText',text:ed.value})};
document.getElementById('upd').onclick=()=>{const full=R.textContent+ed.value;lastSent=full;send({type:'updateText',text:full,readCharCount:R.textContent.length})};
document.getElementById('pause').onclick=()=>send({type:'pause'});
document.getElementById('stop').onclick=()=>send({type:'stop'});
function handle(s){
  active=s.isActive;
  S.textContent=s.isActive?(s.isPaused?'En pausa':s.isMuted?'Micrófono silenciado':s.isListening?'Escuchando…':'Activo'):'Teleprompter detenido';
  const words=s.words.join(' ');
  if(s.isActive&&words){
    const h=Math.min(s.highlightedCharCount,words.length);
    // Lo leído queda bloqueado; sólo se edita lo pendiente.
    R.style.display=h>0?'block':'none';
    if(R.textContent!==words.slice(0,h)){R.textContent=words.slice(0,h);R.scrollTop=R.scrollHeight}
    if(document.activeElement!==ed){ed.value=words.slice(h).replace(/^\\s+/,'')}
  }else{R.style.display='none'}
  const bars=wave.children;s.audioLevels.forEach((l,i)=>{bars[i].style.height=Math.max(2,l*22)+'px'});
  document.querySelector('#prog div').style.width=(s.totalCharCount?100*s.highlightedCharCount/s.totalCharCount:0)+'%';
}
function connect(){ws=new WebSocket('ws://'+location.host+'/ws?t='+encodeURIComponent(token));
  ws.onopen=()=>{S.textContent='Conectado'};
  ws.onmessage=e=>{try{handle(JSON.parse(e.data))}catch(x){console.error(x)}};
  ws.onclose=()=>{S.textContent='Desconectado, reintentando…';setTimeout(connect,1500)}}
connect();
</script></body></html>''';
