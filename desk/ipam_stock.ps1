# 이팜 재고현황 저장 (재고관리 > 재고현황및재고수정 > 최근6개월 · 사용약품전체 · 현재고(+) > 조회 > 미리보기 출력 > 변환 XLSX)
# 사용: powershell -NoProfile -File ipam_stock.ps1 -OutPath "C:\...\재고현황및재고수정261028.xlsx" [-LogPath 로그.txt]
# PC 약국비서의 "이팜에서 재고 가져오기" 단추가 부름 (main.js epharm-stock). 실패하면 로그 마지막 줄이 "... 실패: 이유"
# 이팜 화면 단추들은 이름만 보이고 눌러지지 않아서(UI Automation 패턴 없음), 매번 이름으로 위치를 새로 찾아 마우스로 누름.
# 이름 없는 칸은 가까운 이름 있는 칸(검색상세구분·관리약품·초기화)을 기준으로 떨어진 거리로 찾음. 2026-10-28 1920x1080 최대화 화면에서 잰 값.
# 자료를 바꾸는 단추(재고수정모드·재고수정·Zero처리·재고정리·재고이동·약품정보이동)는 절대 누르지 않음.
param([Parameter(Mandatory=$true)][string]$OutPath,[string]$LogPath='')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public class EW {
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern void keybd_event(byte k,byte s,int f,int e);
}
"@
[void][EW]::SetProcessDPIAware()
$A = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$root = $A::RootElement
$log = if ($LogPath) { $LogPath } else { Join-Path $PSScriptRoot '재고저장_로그.txt' }

function Log($msg) { $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg; Add-Content -Path $log -Value $line -Encoding UTF8; Write-Output $line }
function Fail($msg) { Log ('실패: ' + $msg); exit 1 }

function Click($x, $y) { [void][EW]::SetCursorPos([int]$x, [int]$y); Start-Sleep -Milliseconds 150; [EW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60; [EW]::mouse_event(4,0,0,0,0) }
# 이름 있는 단추 누르기: 위치가 0.4초 동안 그대로인지, 그 자리에 실제로 그 단추가 있는지 확인한 뒤 누름
function ClickEl($el) {
  $name = $el.Current.Name
  for ($k = 0; $k -lt 10; $k++) {
    $r1 = $el.Current.BoundingRectangle; Start-Sleep -Milliseconds 400; $r2 = $el.Current.BoundingRectangle
    $x = [int]($r2.X + $r2.Width/2); $y = [int]($r2.Y + $r2.Height/2)
    if ($r1 -eq $r2 -and -not $el.Current.IsOffscreen) {
      [void][EW]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 200
      $at = $null; try { $at = $A::FromPoint((New-Object System.Windows.Point($x, $y))) } catch {}
      $ok = $false; $e = $at
      for ($u = 0; $e -and $u -lt 4; $u++) { if ($e.Current.Name -eq $name) { $ok = $true; break }; $e = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($e) }
      if ($ok) { Log "누름 '$name' ($x,$y)"; Click $x $y; return }
    }
    Start-Sleep -Milliseconds 500
  }
  Fail "'$name' 단추 자리를 확인 못 함 (움직이거나 다른 창에 가려짐)"
}
# 엉뚱한 질문 창(초기화 등)이 뜨면 아니오 누르고 멈춤
function NoSurprise($m) {
  foreach ($n in '초기화 하시겠습니까 ?','다른 이름으로 저장 확인') {
    $d = ByName $m $n
    if ($d) { foreach ($b in '아니오(N)','아니요(N)') { $no = ByName $m $b; if ($no) { $r = $no.Current.BoundingRectangle; Click ($r.X + $r.Width/2) ($r.Y + $r.Height/2); break } }; Fail "예상 못 한 질문 창 '$n' → 아니오 누르고 멈춤" }
  }
}
function Rect($el) { $el.Current.BoundingRectangle }
function ByName($parent, $name) { $parent.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, $name))) }
function ByNameType($parent, $name, $type) {
  $c = New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, $name)), (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $type)))
  $parent.FindFirst($Scope::Descendants, $c)
}
function ById($parent, $id) { $parent.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, $id))) }
function Need($el, $what) { if (-not $el) { Fail "$what 못 찾음" }; $el }
# 몇 초까지 기다리며 찾기
function WaitFor([scriptblock]$find, $sec, $what) {
  $t = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $t) { $e = & $find; if ($e) { return $e }; Start-Sleep -Milliseconds 300 }
  Fail "$what 이(가) ${sec}초 안에 안 나타남"
}
function WaitGone([scriptblock]$find, $sec, $what) {
  $t = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $t) { if (-not (& $find)) { return }; Start-Sleep -Milliseconds 300 }
  Fail "$what 이(가) ${sec}초 안에 안 닫힘"
}
# 체크칸 켜짐 여부: 칸 가운데 11x11 안의 진한 점 수 (켜짐 약 7, 꺼짐 0)
function IsChecked($x, $y) {
  $bmp = New-Object System.Drawing.Bitmap 11,11; $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen([int]$x-5, [int]$y-5, 0, 0, $bmp.Size); $n = 0
  for ($i=0; $i -lt 11; $i++) { for ($j=0; $j -lt 11; $j++) { $c = $bmp.GetPixel($i,$j); if (($c.R+$c.G+$c.B)/3 -lt 110) { $n++ } } }
  $g.Dispose(); $bmp.Dispose(); $n -ge 3
}
function SetCheck($x, $y, $want, $what) {
  if ((IsChecked $x $y) -ne $want) { Click $x $y; Start-Sleep -Milliseconds 400 }
  if ((IsChecked $x $y) -ne $want) { Fail "$what 체크 상태를 못 맞춤" }
}
function TopWins { $root.FindAll($Scope::Children, [System.Windows.Automation.Condition]::TrueCondition) }
function MainWin { foreach ($w in TopWins) { try { if ($w.Current.Name -like '이팜 (Ver*') { return $w } } catch {} } }
function CountBox($form) {
  # 약품종수 칸 = '재고수정일' 줄에 있는 숫자 EDIT 중 가장 왼쪽
  $anchor = ByName $form '재고수정일'; if (-not $anchor) { return $null }
  $ay = (Rect $anchor).Y; $best = $null
  $c = New-Object System.Windows.Automation.PropertyCondition($A::ClassNameProperty, 'WindowsForms10.EDIT.app.0.338574f_r15_ad1')
  foreach ($e in $form.FindAll($Scope::Descendants, $c)) {
    $r = Rect $e
    if ([Math]::Abs($r.Y - $ay) -lt 15 -and $e.Current.Name -match '^[\d,]+$' -and $r.X -gt (Rect $anchor).X + 150) { if (-not $best -or $r.X -lt (Rect $best).X) { $best = $e } }
  }
  $best
}

Log "시작 OutPath=$OutPath"
$outDir = Split-Path $OutPath -Parent
if (-not (Test-Path $outDir)) { Fail "저장 폴더 없음: $outDir" }

# 1. 이팜 본창 최대화·앞으로
$m = MainWin; if (-not $m) { Fail '이팜 본창 (이팜 (Ver...)) 없음' }
$h = [IntPtr]$m.Current.NativeWindowHandle
[void][EW]::ShowWindow($h, 3); [void][EW]::SetForegroundWindow($h); Start-Sleep -Milliseconds 800
# 윈도우가 앞으로 가져오기를 막으면 Alt 한 번 눌렀다 떼고 다시 (그래도 안 되면 엉뚱한 창을 누르지 않게 멈춤)
if ([EW]::GetForegroundWindow() -ne $h) { [EW]::keybd_event(0x12,0,0,0); [EW]::keybd_event(0x12,0,2,0); [void][EW]::SetForegroundWindow($h); Start-Sleep -Milliseconds 800 }
if ([EW]::GetForegroundWindow() -ne $h) { Fail '이팜 창을 앞으로 가져오지 못함' }
foreach ($n in '출력 미리보기','다른 이름으로 저장','다른 이름으로 저장 확인','내보내기','XLSX 내보내기 옵션') { if (ByName $m $n) { Fail "시작 전에 이미 '$n' 창이 열려 있음" } }

# 2. 재고현황및재고수정 화면 (열려 있으면 그 탭, 없으면 재고관리 메뉴 6번째 항목)
function Form { $f = ByNameType $m '재고현황및재고수정' ([System.Windows.Automation.ControlType]::Window); if ($f -and (Rect $f).X -ge 0) { $f } }
$form = Form
if (-not $form) {
  Click 284 29   # 맨 위 메뉴 '재고관리' (메뉴줄은 이름이 안 보임: standaloneBarDockControl1 안, 창 왼쪽 위 고정 위치)
  $pop = WaitFor { foreach ($w in TopWins) { try { if ($w.Current.ClassName -like 'WindowsForms10.Window.20808*') { return $w } } catch {} } } 3 '재고관리 메뉴'
  $pr = Rect $pop
  Click ($pr.X + 105) ($pr.Y + 133)   # 6번째 항목 '재고현황및재고수정' (항목 간격 약 24)
  $form = WaitFor { Form } 15 '재고현황및재고수정 화면'
  Start-Sleep -Seconds 1
}
Log '재고현황및재고수정 화면 찾음'

# 3. 검색기간 빠른선택 ▼ → 최근6개월 (10번째 항목). ▼ = 검색상세구분 왼쪽 12, 위에서 13
$grp = Need (ByName $form '검색상세구분') '검색상세구분'
$gr = Rect $grp
Click ($gr.X - 12) ($gr.Y + 13); Start-Sleep -Milliseconds 700
Click ($gr.X + 19) ($gr.Y + 167)   # 목록 첫 항목이 ▼ 아래 10, 간격 14.6 → 10번째
Start-Sleep -Milliseconds 600
$from = (Get-Date).AddMonths(-6).ToString('yyyy-MM-dd'); $to = (Get-Date).ToString('yyyy-MM-dd')
$okFrom = ByName $form $from; $okTo = ByName $form $to
if (-not $okFrom -or -not $okTo) { Fail "검색기간이 $from ~ $to 로 안 바뀜" }
Log "검색기간 $from ~ $to"

# 4. 검색상세구분: 사용약품전체만 켬 (기간사용약품·약품사용유무 끔)
SetCheck ($gr.X + 12) ($gr.Y + 32) $false '기간사용약품'
SetCheck ($gr.X + 12) ($gr.Y + 55) $true '사용약품전체'
SetCheck ($gr.X + 12) ($gr.Y + 78) $false '약품사용유무'
Log '사용약품전체 체크'

# 5. 재고조회구분 ▼ → 현재고(+) (2번째 항목). ▼ = 관리약품 묶음 왼쪽 위에서 (601, 28)
$mg = Need (ByName $form '관리약품') '관리약품'
$mr = Rect $mg
Click ($mr.X + 601) ($mr.Y + 28); Start-Sleep -Milliseconds 700
Click ($mr.X + 525) ($mr.Y + 62)   # 목록: 전체 / 현재고(+) / ... 간격 약 15
Start-Sleep -Milliseconds 600
Log '재고조회구분 현재고(+) 선택 (화면에서 값 확인 불가 - 결과 행수로 확인)'

# 6. 조회 → 약품종수 숫자가 멈출 때까지
ClickEl (Need (ByName $form '조회') '조회 단추')
$t = (Get-Date).AddSeconds(60); $last = ''; $same = 0
while ((Get-Date) -lt $t) {
  Start-Sleep -Milliseconds 700
  $cb = CountBox $form; $v = if ($cb) { $cb.Current.Name } else { '' }
  if ($v -match '^[\d,]+$' -and $v -ne '0') { if ($v -eq $last) { $same++ } else { $same = 0; $last = $v }; if ($same -ge 2) { break } }
}
if ($same -lt 2) { Fail '조회 결과(약품종수)가 안 나옴' }
$count = [int]($last -replace ',','')
if ($count -lt 500) { Fail "약품종수 $count — 너무 적음 (조회 조건 확인 필요)" }
Log "조회 완료 약품종수=$count"
Start-Sleep -Milliseconds 1500
NoSurprise $m

# 7. 미리보기 켜고 출력. 미리보기 칸 = 초기화 단추 왼쪽 위에서 (9, 54)
$ini = Need (ByName $form '초기화') '초기화 단추'
$ir = Rect $ini
SetCheck ($ir.X + 9) ($ir.Y + 54) $true '미리보기'
ClickEl (Need (ByName $form '출력') '출력 단추')
$pv = WaitFor { NoSurprise $m; ByName $m '출력 미리보기' } 60 '출력 미리보기 창'
Start-Sleep -Seconds 2
$pr = Rect $pv
Log '출력 미리보기 열림'

# 8. 변환 ▼ → XLSX 파일 (6번째). 미리보기 창 왼쪽 위 기준 변환 (478,128), XLSX (534,368)
Click ($pr.X + 478) ($pr.Y + 128); Start-Sleep -Milliseconds 900
Click ($pr.X + 534) ($pr.Y + 368)
$opt = WaitFor { ByName $m 'XLSX 내보내기 옵션' } 10 'XLSX 내보내기 옵션 창'
ClickEl (Need (ByName $opt '확인') 'XLSX 옵션 확인 단추')

# 9. 다른 이름으로 저장: 임시 이름으로 저장 → 나중에 OutPath 로 옮김 (덮어쓰기 질문을 피함)
$sa = WaitFor { ByName $m '다른 이름으로 저장' } 15 '다른 이름으로 저장 창'
Start-Sleep -Milliseconds 800
# 임시 파일은 재고현황 폴더 밖(TEMP)에 둠: 폴더 자동 읽기가 쓰는 중인 파일을 읽지 않게
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('이팜저장_' + (Get-Date -Format 'HHmmssfff') + '.xlsx')
$host1 = Need (ById $sa 'FileNameControlHost') '파일 이름 칸'
$hr = Rect $host1
Click ($hr.X + 40) ($hr.Y + $hr.Height/2); Start-Sleep -Milliseconds 300
Set-Clipboard -Value $tmp
[System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 150
[System.Windows.Forms.SendKeys]::SendWait('^v'); Start-Sleep -Milliseconds 500
$fnv = $sa.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, '1001')), (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Pane)))))
if (-not $fnv -or $fnv.Current.Name -ne $tmp) { Fail "파일 이름이 안 들어감 (지금: '$($fnv.Current.Name)')" }
# 저장 단추: 이름 '저장(S)' + 종류 Pane (파일 목록 항목도 AutomationId 1 이라 id 로 찾으면 안 됨)
ClickEl (Need (ByNameType $sa '저장(S)' ([System.Windows.Automation.ControlType]::Pane)) '저장(S) 단추')
Start-Sleep -Seconds 1
NoSurprise $m

# 10. "이 파일을 여시겠습니까?" → 아니오
$q = WaitFor { ByName $m '내보내기' } 60 '내보내기 완료 질문 창'
ClickEl (Need (ByName $q '아니오(N)') '아니오(N) 단추')
WaitGone { ByName $m '내보내기' } 5 '내보내기 질문 창'

# 11. 미리보기 닫기 (미리보기 창 왼쪽 위 기준 닫기 (830,108))
$pv = ByName $m '출력 미리보기'
if ($pv) { $pr = Rect $pv; Click ($pr.X + 830) ($pr.Y + 108); WaitGone { ByName $m '출력 미리보기' } 5 '출력 미리보기 창' }

# 12. 임시 파일 → OutPath, 확인
if (-not (Test-Path $tmp)) { Fail "저장된 파일이 없음: $tmp" }
Move-Item -LiteralPath $tmp -Destination $OutPath -Force
$fi = Get-Item -LiteralPath $OutPath
if (((Get-Date) - $fi.LastWriteTime).TotalSeconds -gt 60) { Fail '파일 시각이 1분보다 오래됨' }
Log "성공: $OutPath ($([int]($fi.Length/1KB))KB, 약품종수 $count)"
exit 0
