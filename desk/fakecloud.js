// 시험용 가짜 클라우드 (DESK_FAKE_CLOUD 또는 ?fake=포트 일 때만). 평소에는 아무 일도 안 함.
(()=>{const port=(window.desk&&window.desk.fakeCloudPort)||new URLSearchParams(location.search).get('fake');if(!port)return;
window.__fakeCloud=()=>{
 const ws=new WebSocket('ws://127.0.0.1:'+port);let n=0;const wait={},watchers={};let authCb=null;
 const ready=new Promise(r=>ws.onopen=r);
 ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.rid&&wait[m.rid]){wait[m.rid](m.data);delete wait[m.rid]}if(m.snap!==undefined)(watchers[m.key]||[]).forEach(f=>f(m.snap))};
 const call=async(op,args)=>{await ready;const rid=++n;return new Promise(r=>{wait[rid]=r;ws.send(JSON.stringify({rid,op,...args}))})};
 const setU=u=>{if(u)localStorage.setItem('fakeUser',JSON.stringify(u));else localStorage.removeItem('fakeUser');authCb&&authCb(u)};
 return{onAuth:cb=>{authCb=cb;const s=localStorage.getItem('fakeUser');setTimeout(()=>cb(s?JSON.parse(s):null),0)},
  login:async e=>setU({uid:'u_'+e.replace(/\W/g,''),email:e}),signup:async e=>setU({uid:'u_'+e.replace(/\W/g,''),email:e}),reset:async()=>{},deleteMe:async()=>{window.__fakeDeleted=(window.__fakeDeleted||0)+1},logout:async()=>setU(null),
  asNewUser:async(e,p,fn)=>{if(e.includes('taken'))throw{code:'auth/email-already-in-use'};await fn({set:(path,d,merge)=>call('set',{path,data:d,merge:!!merge})},'u_'+e.replace(/\W/g,''))},changePw:async(o,n)=>{if(o!=='123456')throw{code:'auth/invalid-credential'}},
  changeEmail:async(pw,ne)=>{if(pw!=='123456')throw{code:'auth/invalid-credential'};if(ne.includes('taken'))throw{code:'auth/email-already-in-use'};window.__fakeEmailSent=ne},
  get:p=>call('get',{path:p}),getAll:c=>call('getAll',{path:c}),set:(p,d,merge)=>call('set',{path:p,data:d,merge:!!merge}),del:p=>call('del',{path:p}),
  watchCol:(c,cb)=>{const k='c:'+c;(watchers[k]=watchers[k]||[]).push(cb);call('watch',{key:k});return()=>{watchers[k]=watchers[k].filter(f=>f!==cb)}},
  watchDoc:(p,cb)=>{const k='d:'+p;(watchers[k]=watchers[k]||[]).push(cb);call('watch',{key:k});return()=>{watchers[k]=watchers[k].filter(f=>f!==cb)}}}}})();
