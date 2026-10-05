// 알림 계산 (메인 프로세스용). 화면 쪽 parts_memo.js와 같은 규칙.
const pad2=n=>String(n).padStart(2,'0');
const WD='일월화수목금토';
const REP={once:'한 번',daily:'매일',weekday:'평일(월~금)',weekly:'매주',monthly:'매월',monthEnd:'매월 말일'};
const ymd=d=>`${d.getFullYear()}-${pad2(d.getMonth()+1)}-${pad2(d.getDate())}`;
const lastDay=d=>new Date(d.getFullYear(),d.getMonth()+1,0).getDate();
function aStart(a){const [y,m,d]=a.date.split('-').map(Number);const [h,mi]=(a.time||'09:00').split(':').map(Number);return new Date(y,m-1,d,h,mi)}
function aMatch(a,d){switch(a.rep){case 'daily':return true;case 'weekday':return d.getDay()>0&&d.getDay()<6;case 'weekly':return (a.days||[]).includes(d.getDay());
 case 'monthly':return d.getDate()===Math.min(+a.dom||1,lastDay(d));case 'monthEnd':return d.getDate()===lastDay(d);default:return ymd(d)===a.date}}
function occOn(a,d){const [h,mi]=(a.time||'09:00').split(':').map(Number);return new Date(d.getFullYear(),d.getMonth(),d.getDate(),h,mi)}
function latestOcc(a,now){const st=aStart(a);if(a.rep==='once')return st<=now?st:null;
 for(let i=0;i<62;i++){const d=new Date(now.getFullYear(),now.getMonth(),now.getDate()-i);const o=occOn(a,d);if(o>now||!aMatch(a,d))continue;if(o<st)return null;return o}return null}
function whenLabel(o){if(!o)return '';const n=new Date(),t=new Date(n.getFullYear(),n.getMonth(),n.getDate());const dd=Math.round((new Date(o.getFullYear(),o.getMonth(),o.getDate())-t)/864e5);
 const day=dd===0?'오늘':dd===1?'내일':dd===-1?'어제':`${o.getMonth()+1}/${o.getDate()} (${WD[o.getDay()]})`;return `${day} ${pad2(o.getHours())}:${pad2(o.getMinutes())}`}
function repLabel(a){if(a.rep==='weekly')return '매주 '+(a.days||[]).slice().sort().map(x=>WD[x]).join('·');if(a.rep==='monthly')return `매월 ${a.dom}일${a.dom>28?'(없으면 말일)':''}`;if(a.rep==='once')return '한 번';return REP[a.rep]||''}
function dueAlarms(alarms,now=new Date(),me='local'){return (alarms||[]).filter(a=>{if(!a.on||!a.date)return false;if(a.to&&a.to.length&&!a.to.includes(me))return false;const o=latestOcc(a,now);
 const ack=Math.max(a.ack||0,(a.acks||{})[me]||0),snz=Math.max(a.snooze||0,(a.snz||{})[me]||0);return o&&o.getTime()>ack&&!(snz>now.getTime())})}
module.exports={dueAlarms,latestOcc,whenLabel,repLabel,ymd};
