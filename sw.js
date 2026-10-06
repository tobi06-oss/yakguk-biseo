const V='pharm-1791275294';
self.addEventListener('install',e=>{self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k.startsWith('pharm-')&&k!==V).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin)return;
 // 화면(html)은 새 버전을 먼저, 나머지(글꼴·라이브러리)는 저장해 둔 것을 먼저
 if(e.request.mode==='navigate'||u.pathname.endsWith('.html')||u.pathname.endsWith('/')||u.pathname.endsWith('.json')){e.respondWith(fetch(e.request).then(r=>{const c=r.clone();caches.open(V).then(x=>x.put(e.request,c));return r}).catch(()=>caches.match(e.request)))}
 else e.respondWith(caches.match(e.request).then(m=>m||fetch(e.request).then(r=>{const c=r.clone();caches.open(V).then(x=>x.put(e.request,c));return r})))});
self.addEventListener('notificationclick',e=>{e.notification.close();e.waitUntil(self.clients.matchAll({type:'window'}).then(cs=>cs.length?cs[0].focus():self.clients.openWindow('./')))});

// 서버가 보낸 푸시(앱이 닫혀 있어도 도착) → 알림으로 표시
self.addEventListener('push',e=>{let d={};try{d=e.data.json()}catch(_){d={body:e.data?e.data.text():''}}
 e.waitUntil(self.registration.showNotification(d.title||'약국비서 알림',{body:d.body||'',tag:d.tag||'pharm-alarm',renotify:true,requireInteraction:true,icon:'icon-192.png',badge:'icon-192.png'}))});
