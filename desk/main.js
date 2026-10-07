const {app,BrowserWindow,Tray,Menu,ipcMain,dialog,screen,nativeImage,globalShortcut,shell}=require('electron');
const path=require('path'),fs=require('fs');
const core=require('./alarmcore');
const crypto=require('crypto');
// boot.js 없이 바로 켠 경우(예전 방식)에도 동작하도록
const DESK=global.__desk||{bundledDir:__dirname,bundledVersion:require('./package.json').version,appDir:__dirname,version:require('./package.json').version,updatesDir:null,cmp:(a,b)=>String(a).localeCompare(String(b),undefined,{numeric:true}),ok(){}};
const VERSION=DESK.version;
const UPDATE_URL=process.env.DESK_UPDATE_URL||'https://tobi06-oss.github.io/yakguk-biseo/desk/';

app.setAppUserModelId('kr.chambareun.assistant');
app.commandLine.appendSwitch('autoplay-policy','no-user-gesture-required');
if(process.env.DESK_DATA)app.setPath('userData',process.env.DESK_DATA);
if(!(global.__desk&&global.__desk.locked)&&!app.requestSingleInstanceLock()){app.quit();process.exit(0)}

const ICON=path.join(__dirname,'icon.png');
let DATA_DIR,DATA_FILE,data={docs:{},desk:{}};
let win=null,tray=null,popup=null,quitting=false,popupItems=[],brief=null;
const stickyWins=new Map();
const startHidden=process.argv.includes('--hidden');

/* ---------- 저장 ---------- */
function loadData(){
 DATA_DIR=app.getPath('userData');DATA_FILE=path.join(DATA_DIR,'data.json');
 try{data=JSON.parse(fs.readFileSync(DATA_FILE,'utf8'))}catch(e){
  try{data=JSON.parse(fs.readFileSync(DATA_FILE+'.bak','utf8'))}catch(e2){data={docs:{},desk:{}}}
  if(!Object.keys(data.docs||{}).length){ // 첫 실행: 같이 들어 있는 기본 자료
   try{data.docs=JSON.parse(fs.readFileSync(path.join(DESK.bundledDir,'seed.json'),'utf8'))}catch(e3){data.docs={}}
  }
 }
 data.docs=data.docs||{};data.desk=data.desk||{};
 if(data.desk.autostart===undefined){data.desk.autostart=true;setAutostart(true)}
}
let saveTimer=null;
function saveData(now){clearTimeout(saveTimer);const w=()=>{try{fs.mkdirSync(DATA_DIR,{recursive:true});const tmp=DATA_FILE+'.tmp';fs.writeFileSync(tmp,JSON.stringify(data));
  if(fs.existsSync(DATA_FILE))fs.copyFileSync(DATA_FILE,DATA_FILE+'.bak');fs.renameSync(tmp,DATA_FILE)}catch(e){console.error('save',e)}};
 if(now)w();else saveTimer=setTimeout(w,300)}
const memo=()=>data.docs['memo/main']||(data.docs['memo/main']={memos:[],alarms:[]});
function setDoc(p,d,fromRenderer){data.docs[p]=d;saveData();if(!fromRenderer&&win)win.webContents.send('changed',p,d);if(p==='memo/main'){syncStickies();checkAlarms()}}

function setAutostart(on){try{app.setLoginItemSettings({openAtLogin:!!on,args:['--hidden']})}catch(e){}}

/* ---------- 메인 창 ---------- */
function createWin(){
 const b=data.desk.bounds||{width:480,height:860};
 win=new BrowserWindow({...b,minWidth:380,minHeight:560,show:false,icon:ICON,title:'참바른약국 비서',backgroundColor:'#F5F6F9',autoHideMenuBar:true,
  webPreferences:{preload:path.join(__dirname,'preload.js'),contextIsolation:true,nodeIntegration:false,backgroundThrottling:false,webSecurity:false}});
 if(data.desk.winTop)win.setAlwaysOnTop(true);
 if(data.desk.side)setTimeout(()=>applySide(true,true),0);
 win.loadFile(path.join(__dirname,'index.html'));
 win.webContents.once('did-finish-load',()=>DESK.ok()); // 새 버전이 잘 켜졌음
 // 업데이트로 다시 켜졌거나 버전이 바뀐 첫 실행이면 숨김(--hidden)이어도 창을 띄움
 const justUpdated=!!data.desk.showNext||(data.desk.lastVersion?data.desk.lastVersion!==VERSION:!!(DESK.bundledVersion&&DESK.cmp(VERSION,DESK.bundledVersion)>0));data.desk.showNext=false;data.desk.lastVersion=VERSION;saveData();
 win.once('ready-to-show',()=>{if(!startHidden||justUpdated){win.show();win.focus()}});
 const keep=()=>{if(data.desk.side)return;if(!win.isMaximized()&&!win.isMinimized())data.desk.bounds=win.getBounds();saveData()};
 win.on('resized',keep);win.on('moved',keep);
 win.on('close',e=>{if(quitting)return;e.preventDefault();win.hide();
  if(!data.desk.trayTold&&tray&&process.platform==='win32'){data.desk.trayTold=true;saveData();tray.displayBalloon({iconType:'info',title:'참바른약국 비서',content:'창을 닫아도 알림은 계속 와요. 오른쪽 아래 트레이 아이콘에서 다시 열 수 있어요.'})}});
 win.webContents.setWindowOpenHandler(({url})=>{shell.openExternal(url);return{action:'deny'}});
}
function showWin(cmd){if(!win)return;if(win.isMinimized())win.restore();win.show();win.focus();if(cmd)win.webContents.send('command',cmd)}

/* ---------- 트레이 ---------- */
function buildTray(){
 tray=new Tray(nativeImage.createFromPath(ICON).resize({width:16,height:16}));tray.setToolTip('참바른약국 비서');
 const menu=()=>Menu.buildFromTemplate([
  {label:'열기',click:()=>showWin()},
  {label:'새 메모',click:()=>showWin('newMemo')},
  {label:'새 알림',click:()=>showWin('newAlarm')},
  {type:'separator'},
  {label:'윈도우 켤 때 자동 실행',type:'checkbox',checked:!!data.desk.autostart,click:i=>{data.desk.autostart=i.checked;setAutostart(i.checked);saveData()}},
  {type:'separator'},
  {label:'끝내기',click:()=>{quitting=true;app.quit()}}]);
 tray.setContextMenu(menu());tray.on('click',()=>showWin());tray.on('right-click',()=>tray.setContextMenu(menu()));
}

/* ---------- 포스트잇 알림 창 (항상 위, 화면 중앙) ---------- */
let shownKeys=new Set();
let workInit=false;
function checkAlarms(){if(!workInit){workInit=true;core.setWork(data.desk&&data.desk.work)}
 const now=new Date();const me=data.desk.me||'local';const due=core.dueAlarms(memo().alarms,now,me);
 const items=due.map(a=>{const o=core.latestOcc(a,now);return{kind:'alarm',id:a.id,text:a.text,color:a.color||'yellow',when:core.whenLabel(o),rep:core.repLabel(a),late:now-o>15*60e3,key:a.id+':'+o.getTime()}});
 if(brief)items.unshift(brief);
 (data.desk.notices||[]).forEach(n=>items.unshift({kind:'notice',key:'n:'+n.id,...n}));
 const fresh=items.some(x=>!shownKeys.has(x.key));items.forEach(x=>shownKeys.add(x.key));
 popupItems=items;
 if(!items.length){if(popup&&!popup.isDestroyed())popup.close();return}
 if(!popup||popup.isDestroyed())openPopup(fresh);else{popup.webContents.send('items',items,fresh);if(fresh){popup.setAlwaysOnTop(true,'screen-saver');popup.showInactive();popup.moveTop()}}
}
function openPopup(ring){
 const wa=screen.getPrimaryDisplay().workArea;const w=430,h=320;
 popup=new BrowserWindow({width:w,height:h,x:Math.round(wa.x+(wa.width-w)/2),y:Math.round(wa.y+(wa.height-h)/2),frame:false,transparent:true,resizable:false,skipTaskbar:false,
  alwaysOnTop:true,show:false,focusable:true,icon:ICON,title:'알림',hasShadow:false,webPreferences:{preload:path.join(__dirname,'preload.js'),contextIsolation:true,backgroundThrottling:false}});
 popup.setAlwaysOnTop(true,'screen-saver');popup.setVisibleOnAllWorkspaces(true);
 popup.loadFile(path.join(__dirname,'popup.html'));
 popup.webContents.once('did-finish-load',()=>{popup.webContents.send('items',popupItems,ring);popup.show();popup.moveTop();if(process.platform==='win32')popup.flashFrame(true)});
 popup.on('closed',()=>{popup=null});
}
ipcMain.on('popup-fit',(e,hgt)=>{if(!popup||popup.isDestroyed())return;const wa=screen.getPrimaryDisplay().workArea;const h=Math.min(Math.ceil(hgt),wa.height-40),w=430;
 popup.setBounds({width:w,height:h,x:Math.round(wa.x+(wa.width-w)/2),y:Math.round(wa.y+(wa.height-h)/2)})});
ipcMain.on('alarm-act',(e,id,act)=>{
 if(String(id).startsWith('n:')){data.desk.notices=(data.desk.notices||[]).filter(n=>'n:'+n.id!==id);if(win)win.webContents.send('notice-read',id.slice(2));checkAlarms();return}
 if(id==='__brief'){brief=null;if(act==='open')showWin('openStock');checkAlarms();return}
 const m=memo();const a=m.alarms.find(x=>x.id===id);if(!a)return;
 const me=data.desk.me||'local';a.acks=a.acks||{};a.snz=a.snz||{};
 if(act==='ok'){a.acks[me]=Date.now();a.snz[me]=0}
 else if(act==='tomorrow'){const t=new Date();t.setDate(t.getDate()+1);t.setHours(9,0,0,0);a.snz[me]=t.getTime()}
 else a.snz[me]=Date.now()+(+act)*60e3;
 setDoc('memo/main',{...m,savedAt:new Date().toISOString()});
});
ipcMain.on('set-me',(e,me)=>{data.desk.me=me||'local';saveData();checkAlarms()});
// 알림 모드 + 내 근무일(약국 캘린더) — 종 단추
ipcMain.on('set-work',(e,w)=>{if(JSON.stringify(data.desk.work||null)===JSON.stringify(w||null))return;data.desk.work=w||null;core.setWork(data.desk.work);saveData();checkAlarms()});
ipcMain.on('set-notices',(e,list)=>{data.desk.notices=list||[];checkAlarms()});
ipcMain.on('show-brief',(e,b)=>{brief={kind:'brief',key:'brief:'+Date.now(),...b};checkAlarms()});

/* ---------- 바탕화면 메모 ---------- */
function syncStickies(){
 const ms=memo().memos.filter(m=>m.desk);const ids=new Set(ms.map(m=>m.id));
 for(const [id,w] of stickyWins){if(!ids.has(id)){if(!w.isDestroyed())w.destroy();stickyWins.delete(id)}}
 ms.forEach((m,i)=>{let w=stickyWins.get(m.id);
  if(!w||w.isDestroyed()){const wa=screen.getPrimaryDisplay().workArea;const d=m.desk||{};
   w=new BrowserWindow({width:d.w||240,height:d.h||220,x:d.x??(wa.x+wa.width-270-i*24),y:d.y??(wa.y+30+i*24),frame:false,transparent:false,minWidth:160,minHeight:120,skipTaskbar:true,
    alwaysOnTop:!!d.top,show:false,icon:ICON,title:'메모',backgroundColor:'#FFF3B0',webPreferences:{preload:path.join(__dirname,'preload.js'),contextIsolation:true}});
   w.loadFile(path.join(__dirname,'sticky.html'),{query:{id:m.id}});w.once('ready-to-show',()=>w.showInactive());
   const keep=()=>{const mm=memo().memos.find(x=>x.id===m.id);if(!mm||!mm.desk)return;const b=w.getBounds();Object.assign(mm.desk,{x:b.x,y:b.y,w:b.width,h:b.height});saveData()};
   w.on('moved',keep);w.on('resized',keep);stickyWins.set(m.id,w)}
  else{w.setAlwaysOnTop(!!(m.desk&&m.desk.top));w.webContents.send('memo',m)}
 });
}
ipcMain.handle('memo-get',(e,id)=>memo().memos.find(x=>x.id===id)||null);
ipcMain.on('memo-update',(e,id,patch)=>{const m=memo();const x=m.memos.find(y=>y.id===id);if(!x)return;
 if(patch.desk===null)x.desk=null;else if(patch.desk)x.desk={...x.desk,...patch.desk};
 if(patch.text!==undefined)x.text=String(patch.text).slice(0,2000);if(patch.color)x.color=patch.color;
 data.docs['memo/main']=m;saveData();if(win)win.webContents.send('changed','memo/main',m);
 if(patch.desk!==undefined){const w=stickyWins.get(id);if(patch.desk===null)syncStickies();else if(w&&!w.isDestroyed())w.setAlwaysOnTop(!!x.desk.top)}
});

/* ---------- 이팜 엑셀 폴더 자동 읽기 ---------- */
function scanFolder(force){
 const dir=data.desk.watchDir;if(!dir||!win)return;let files;
 try{files=fs.readdirSync(dir).filter(f=>/\.(xlsx|xls)$/i.test(f)&&!f.startsWith('~$')).map(f=>{const p=path.join(dir,f);const st=fs.statSync(p);return{p,f,t:st.mtimeMs,size:st.size}})}catch(e){return}
 const seen=data.desk.seen||(data.desk.seen={});
 const news=files.filter(x=>force?x.t>Date.now()-36*3600e3&&!seen[x.p]:x.t>(seen[x.p]||0)&&x.t>(data.desk.watchSince||0)).sort((a,b)=>a.t-b.t);
 news.forEach(x=>{if(Date.now()-x.t<4000)return; // 아직 쓰는 중일 수 있음
  seen[x.p]=x.t;try{const buf=fs.readFileSync(x.p);win.webContents.send('import-file',x.f,buf)}catch(e){}});
 if(news.length)saveData();
}
ipcMain.handle('pick-folder',async()=>{const r=await dialog.showOpenDialog(win,{title:'이팜에서 엑셀을 저장하는 폴더',properties:['openDirectory']});
 if(r.canceled||!r.filePaths[0])return data.desk.watchDir||'';data.desk.watchDir=r.filePaths[0];data.desk.watchSince=Date.now()-36*3600e3;data.desk.seen={};saveData();setTimeout(()=>scanFolder(),500);return data.desk.watchDir});
ipcMain.handle('desk-config',()=>({side:!!data.desk.side,watchDir:data.desk.watchDir||'',autostart:!!data.desk.autostart,lastImport:data.desk.lastImport||null,dataDir:DATA_DIR,version:VERSION,update:upd,winTop:!!data.desk.winTop,sideTop:data.desk.sideTop!==false}));
// 사이드바 모드: 화면 오른쪽 끝에 세로로 길게(항상 위는 핀 단추로 켜고 끔, 기본 켬 = data.desk.sideTop). 끄면 원래 자리·크기로
const SIDE_W=280;
function applySide(on,boot){if(!win||win.isDestroyed())return false;
 if(on){if(!boot&&!data.desk.side)data.desk.bounds=win.getBounds();
  if(win.isMaximized())win.unmaximize();
  const wa=screen.getDisplayMatching(win.getBounds()).workArea;
  win.setMinimumSize(240,400);win.setBounds({x:wa.x+wa.width-SIDE_W,y:wa.y,width:SIDE_W,height:wa.height});win.setAlwaysOnTop(data.desk.sideTop!==false,'floating')}
 else{win.setMinimumSize(380,560);const b=data.desk.bounds||{width:480,height:860};win.setBounds(b);win.setAlwaysOnTop(!!data.desk.winTop)}
 data.desk.side=!!on;saveData();return !!on}
ipcMain.handle('win-side',(e,on)=>applySide(!!on));
// 사이드바에서 패널을 열면 잠깐 기본 폭으로 넓혔다가(오른쪽 끝 기준), 닫으면 다시 사이드바로
ipcMain.handle('win-side-temp',(e,on)=>{if(!win||win.isDestroyed()||!data.desk.side)return false;
 const wa=screen.getDisplayMatching(win.getBounds()).workArea;
 if(on){const w=Math.max(380,Math.min((data.desk.bounds&&data.desk.bounds.width)||480,wa.width));win.setMinimumSize(380,560);win.setBounds({x:wa.x+wa.width-w,y:wa.y,width:w,height:wa.height})}
 else{win.setMinimumSize(240,400);win.setBounds({x:wa.x+wa.width-SIDE_W,y:wa.y,width:SIDE_W,height:wa.height})}
 return !!on});
// 프로그램 창 항상 위
ipcMain.handle('win-top',(e,on)=>{if(data.desk.side){data.desk.sideTop=!!on;saveData();if(win&&!win.isDestroyed())win.setAlwaysOnTop(!!on,'floating')}else{data.desk.winTop=!!on;saveData();if(win&&!win.isDestroyed())win.setAlwaysOnTop(!!on)}return !!on});
ipcMain.on('imported',(e,info)=>{data.desk.lastImport={...info,at:new Date().toISOString()};saveData()});
ipcMain.on('set-autostart',(e,on)=>{data.desk.autostart=!!on;setAutostart(on);saveData()});
ipcMain.on('clear-folder',()=>{data.desk.watchDir='';saveData()});
ipcMain.handle('backup',async()=>{const d=new Date();const r=await dialog.showSaveDialog(win,{title:'백업 파일 저장',defaultPath:`약국비서_백업_${d.getFullYear()}${String(d.getMonth()+1).padStart(2,'0')}${String(d.getDate()).padStart(2,'0')}.json`,filters:[{name:'백업',extensions:['json']}]});
 if(r.canceled||!r.filePath)return false;fs.writeFileSync(r.filePath,JSON.stringify(data.docs));return true});
ipcMain.handle('restore',async()=>{const r=await dialog.showOpenDialog(win,{title:'백업 파일 열기',filters:[{name:'백업',extensions:['json']}],properties:['openFile']});
 if(r.canceled||!r.filePaths[0])return false;try{const d=JSON.parse(fs.readFileSync(r.filePaths[0],'utf8'));if(typeof d!=='object'||!d)return false;saveData(true);
  fs.copyFileSync(DATA_FILE,DATA_FILE+'.before-restore');data.docs=d;saveData(true);win.reload();syncStickies();return true}catch(e){return false}});
if(process.env.DESK_DATA)ipcMain.on('__test_dir',(e,dir)=>{data.desk.watchDir=dir;data.desk.watchSince=0;data.desk.seen={};scanFolder()});
ipcMain.on('open-data-dir',()=>shell.openPath(DATA_DIR));

/* ---------- 자동 업데이트 (GitHub Pages의 desk/ 에서 받음) ---------- */
let upd={state:'idle',version:null,notes:'',err:''};
function updSend(){if(win&&!win.isDestroyed())win.webContents.send('update',upd)}
async function getBuf(u){const {net}=require('electron');const r=await net.fetch(u,{cache:'no-store'});if(!r.ok)throw new Error('HTTP '+r.status+' '+u);return Buffer.from(await r.arrayBuffer())}
async function checkUpdate(manual){
 if(!DESK.updatesDir||upd.state==='downloading')return upd;
 try{upd={...upd,state:'checking',err:''};if(manual)updSend();
  const m=JSON.parse((await getBuf(UPDATE_URL+'update.json?t='+Date.now())).toString('utf8'));
  const U=DESK.updatesDir,v=String(m.version||'');
  if(!/^\d+\.\d+\.\d+$/.test(v)||DESK.cmp(v,VERSION)<=0||fs.existsSync(path.join(U,'bad-'+v))){upd={state:'latest',version:VERSION,notes:'',err:''};if(manual)updSend();return upd}
  if(fs.existsSync(path.join(U,v,'.ok'))){upd={state:'ready',version:v,notes:m.notes||'',err:''};updSend();return upd}
  upd={state:'downloading',version:v,notes:m.notes||'',err:''};updSend();
  const tmp=path.join(U,v+'.tmp');fs.rmSync(tmp,{recursive:true,force:true});fs.mkdirSync(U,{recursive:true});
  fs.cpSync(DESK.bundledDir,tmp,{recursive:true}); // 글꼴 등 바뀌지 않는 파일은 설치된 것을 그대로 씀
  for(const f of m.files||[]){const rel=String(f.p||'');if(!/^[\w\-./]+$/.test(rel)||rel.includes('..')||rel.startsWith('/'))throw new Error('잘못된 파일 이름: '+rel);
   const b=await getBuf(UPDATE_URL+rel+'?v='+v);const h=crypto.createHash('sha256').update(b).digest('hex');if(h!==f.sha256)throw new Error('파일이 깨졌어요: '+rel);
   fs.mkdirSync(path.dirname(path.join(tmp,rel)),{recursive:true});fs.writeFileSync(path.join(tmp,rel),b)}
  if(!fs.existsSync(path.join(tmp,'main.js')))throw new Error('main.js가 없어요');
  fs.rmSync(path.join(U,v),{recursive:true,force:true});fs.renameSync(tmp,path.join(U,v));fs.writeFileSync(path.join(U,v,'.ok'),new Date().toISOString());
  const prev=DESK.cmp(VERSION,DESK.bundledVersion)>0?VERSION:null;
  fs.writeFileSync(path.join(U,'current.json'),JSON.stringify({version:v,prev,at:new Date().toISOString()}));
  // 오래된 업데이트 폴더 정리 (새 것·지금 것만 남김)
  try{for(const n of fs.readdirSync(U)){const keep=[v,VERSION,'current.json'].includes(n)||n.startsWith('bad-');if(!keep&&!n.startsWith('pending-'))fs.rmSync(path.join(U,n),{recursive:true,force:true})}}catch(e){}
  upd={state:'ready',version:v,notes:m.notes||'',err:''};updSend();return upd
 }catch(e){upd={...upd,state:'error',err:String(e&&e.message||e)};if(manual)updSend();return upd}}
ipcMain.handle('update-check',()=>checkUpdate(true));
ipcMain.on('update-restart',()=>{if(upd.state!=='ready')return;quitting=true;data.desk.showNext=true;saveData(true);app.relaunch({args:process.argv.slice(1).filter(a=>a!=='--hidden')});app.exit(0)});

/* ---------- 화면과 주고받기 ---------- */
ipcMain.handle('load-all',()=>data.docs);
ipcMain.handle('save',(e,p,d)=>{setDoc(p,d,true);return true});
ipcMain.on('show-main',(e,cmd)=>showWin(cmd));
ipcMain.on('renderer-ready',()=>{scanFolder(true)});

app.on('second-instance',()=>showWin());
app.on('before-quit',()=>{quitting=true;saveData(true)});
function ensureShortcuts(){if(process.platform!=='win32'||!app.isPackaged)return;
 const opts={target:process.execPath,icon:path.join(__dirname,'icon.ico'),iconIndex:0,description:'참바른약국 비서',appUserModelId:'kr.chambareun.assistant'};
 const sm=path.join(app.getPath('appData'),'Microsoft','Windows','Start Menu','Programs','참바른약국 비서.lnk');
 try{shell.writeShortcutLink(sm,fs.existsSync(sm)?'replace':'create',opts)}catch(e){}
 const dl=path.join(app.getPath('desktop'),'참바른약국 비서.lnk');
 if(!data.desk.shortcuts){try{shell.writeShortcutLink(dl,'create',opts)}catch(e){}data.desk.shortcuts=true;saveData()}
 else if(fs.existsSync(dl)){try{const cur=shell.readShortcutLink(dl);if(cur.target!==process.execPath)shell.writeShortcutLink(dl,'replace',opts)}catch(e){}}
 if(data.desk.autostart)setAutostart(true)}
app.whenReady().then(()=>{
 // Firebase 요청: 로컬 파일에서 보내는 요청이라 웹사이트 주소를 붙여 줌 (API 키 사이트 제한 대비)
 try{require('electron').session.defaultSession.webRequest.onBeforeSendHeaders({urls:['https://*.googleapis.com/*']},(d,cb)=>{d.requestHeaders['Referer']='https://tobi06-oss.github.io/';cb({requestHeaders:d.requestHeaders})})}catch(e){}
 loadData();ensureShortcuts();createWin();buildTray();syncStickies();
 setInterval(checkAlarms,15000);setTimeout(checkAlarms,2500);
 setInterval(()=>scanFolder(),60000);
 setTimeout(()=>checkUpdate(false),20000);setInterval(()=>checkUpdate(false),3600e3);
 try{globalShortcut.register('CommandOrControl+Alt+M',()=>showWin('newMemo'));globalShortcut.register('CommandOrControl+Alt+A',()=>showWin('newAlarm'))}catch(e){}
 // 절전 후 깨어나면 바로 확인
 try{require('electron').powerMonitor.on('resume',()=>{checkAlarms();scanFolder()})}catch(e){}
});
app.on('will-quit',()=>globalShortcut.unregisterAll());
app.on('window-all-closed',e=>{/* 트레이에 남음 */});
