# 이팜 조제약품현황 저장 (조제관리 > 조제내역현황 > 조제약품별 탭 > 최근6개월 > 조제약품현황 조회 > 미리보기 출력 > 변환 XLSX)
# 사용: powershell -NoProfile -File ipam_disp.ps1 -OutPath "C:\...\조제약품현황261028.xlsx" [-LogPath "C:\...\로그.txt"]
# PC 약국비서의 "이팜에서 재고 가져오기" 단추가 ipam_stock.ps1 다음에 부름 (main.js epharm-stock). 실패하면 로그 마지막 줄이 "... 실패: 이유"
# 이팜 화면 단추들은 이름만 보이고 눌러지지 않아서(UI Automation 패턴 없음), 매번 이름으로 위치를 새로 찾아 마우스로 누름.
# 이름 없는 칸은 가까운 이름 있는 칸(날짜 칸·큰 조회 단추·미리보기 창)을 기준으로 떨어진 거리로 찾음. 2026-10-28 1920x1080 최대화 화면에서 잰 값.
# 개인정보: 첫 탭 '조제내역별'은 환자 목록이라, 조회는 반드시 '조제약품별' 탭으로 바꾼 것을 확인한 뒤에만 누름.
#           오른쪽 '처방고객' 칸(환자 목록)의 조회·출력은 절대 누르지 않음. 화면 캡처·표 내용 읽기 없음.
# 자료를 바꾸는 단추는 누르지 않음 (이 화면은 조회·출력만 씀).
param([Parameter(Mandatory=$true)][string]$OutPath, [string]$LogPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms, System.IO.Compression.FileSystem
Add-Type @"
using System; using System.Runtime.InteropServices;
public class EW {
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k,byte s,int f,int e);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,int f);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h,int c);
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[void][EW]::SetProcessDPIAware()
$A = [System.Windows.Automation.AutomationElement]
$Scope = [System.Windows.Automation.TreeScope]
$root = $A::RootElement
$log = if ($LogPath) { $LogPath } else { Join-Path $PSScriptRoot '조제저장_로그.txt' }
$expectCols = '약품명','약품코드','제약회사','사입거래처','조제단위','약품단가','조제수량','조제건수','약가합계','조제개시일','최근조제일','재고총량','재고금액','적정재고','대체'

function Log($msg) { $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg; Add-Content -Path $log -Value $line -Encoding UTF8; Write-Output $line }
function Fail($msg) { Log ('실패: ' + $msg); exit 1 }

function Click($x, $y) { [void][EW]::SetCursorPos([int]$x, [int]$y); Start-Sleep -Milliseconds 150; [EW]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60; [EW]::mouse_event(4,0,0,0,0) }
# 이팜(또는 이팜이 띄운 창)이 맨 앞인지 확인. 아니면 Alt 한 번 누른 뒤 다시 앞으로 (윈도우가 앞으로 가져오기를 막을 때)
function Front {
  for ($k = 0; $k -lt 2; $k++) {
    if ([EW]::GetAncestor([EW]::GetForegroundWindow(), 3) -eq $h) { return }
    if ($k -eq 1) { [EW]::keybd_event(0x12,0,0,0); [EW]::keybd_event(0x12,0,2,0); Start-Sleep -Milliseconds 100 }
    [void][EW]::SetForegroundWindow($h); Start-Sleep -Milliseconds 600
  }
  if ([EW]::GetAncestor([EW]::GetForegroundWindow(), 3) -ne $h) { Fail '이팜 창을 맨 앞으로 못 가져옴 (다른 창이 앞에 있음)' }
}
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
# 엉뚱한 질문 창이 뜨면 아니오 누르고 멈춤
function NoSurprise($m) {
  foreach ($n in '초기화 하시겠습니까 ?','다른 이름으로 저장 확인','CSV 내보내기 옵션') {
    $d = ByName $m $n
    if ($d) { foreach ($b in '아니오(N)','아니요(N)','취소') { $no = ByName $d $b; if ($no) { $r = $no.Current.BoundingRectangle; Click ($r.X + $r.Width/2) ($r.Y + $r.Height/2); break } }; Fail "예상 못 한 창 '$n' → 아니오/취소 누르고 멈춤" }
  }
}
function Rect($el) { $el.Current.BoundingRectangle }
function ByName($parent, $name) { $parent.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, $name))) }
function AllByName($parent, $name) { $parent.FindAll($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, $name))) }
function ByNameType($parent, $name, $type) {
  $c = New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($A::NameProperty, $name)), (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, $type)))
  $parent.FindFirst($Scope::Descendants, $c)
}
function ById($parent, $id) { $parent.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, $id))) }
function Need($el, $what) { if (-not $el) { Fail "$what 못 찾음" }; $el }
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
# 조제약품현황 칸의 조회/출력 단추 = 화면 위쪽(폼 위에서 200 안)·왼쪽 절반에 보이는 것. '조제약품별' 탭일 때만 있음.
# (조제내역별 탭의 조회·출력과 오른쪽 처방고객 칸의 조회·출력은 x가 폼 가운데보다 오른쪽)
function SectionBtn($name) {
  $fr = Rect $form
  foreach ($e in (AllByName $form $name)) {
    $r = Rect $e
    if (-not $e.Current.IsOffscreen -and $r.Width -lt 100 -and $r.X -gt $fr.X -and $r.X -lt $fr.X + $fr.Width/2 -and $r.Y -lt $fr.Y + 200) { return $e }
  }
}
# xlsx 첫 시트에서 제목·검색기간·머리줄·자료 줄 수만 읽음 (자료 내용은 안 읽음)
function CheckXlsx($path) {
  $z = [System.IO.Compression.ZipFile]::OpenRead($path)
  try {
    $rd = { param($n) $en = $z.GetEntry($n); if (-not $en) { return $null }; $s = New-Object System.IO.StreamReader($en.Open(), [Text.Encoding]::UTF8); try { [xml]$s.ReadToEnd() } finally { $s.Close() } }
    $ssx = & $rd 'xl/sharedStrings.xml'
    $ss = @(); if ($ssx) { foreach ($si in $ssx.sst.si) { $ss += ($si.SelectNodes('.//*[local-name()="t"]') | ForEach-Object { $_.InnerText }) -join '' } }
    $sheet = $z.Entries | Where-Object { $_.FullName -like 'xl/worksheets/sheet*.xml' } | Select-Object -First 1
    if (-not $sheet) { return $null }
    $sx = & $rd $sheet.FullName
    $rows = @(); foreach ($r in $sx.worksheet.sheetData.row) {
      $vals = @(); foreach ($c in @($r.c)) { if ($c -and $c.v) { if ($c.t -eq 's') { $vals += $ss[[int]$c.v] } else { $vals += [string]$c.v } } }
      $rows += ,$vals
    }
    $hi = -1; for ($i = 0; $i -lt [Math]::Min(10, $rows.Count); $i++) { if ($rows[$i].Count -ge 4) { $hi = $i; break } }
    if ($hi -lt 0) { return $null }
    $data = 0; for ($i = $hi + 1; $i -lt $rows.Count; $i++) { if ($rows[$i].Count -ge 3) { $data++ } }
    [pscustomobject]@{ Top = (($rows[0..($hi-1)] | ForEach-Object { $_ -join ' ' }) -join ' '); Header = @($rows[$hi] | ForEach-Object { $_ -replace '\s','' }); Rows = $data }
  } finally { $z.Dispose() }
}

Log "시작 OutPath=$OutPath"
$outDir = Split-Path $OutPath -Parent
if (-not (Test-Path $outDir)) { Fail "저장 폴더 없음: $outDir" }

# 1. 이팜 본창 최대화·앞으로
$m = MainWin; if (-not $m) { Fail '이팜 본창 (이팜 (Ver...)) 없음' }
$h = [IntPtr]$m.Current.NativeWindowHandle
[void][EW]::ShowWindow($h, 3); [void][EW]::SetForegroundWindow($h); Start-Sleep -Milliseconds 800
Front
foreach ($n in '출력 미리보기','다른 이름으로 저장','다른 이름으로 저장 확인','내보내기','XLSX 내보내기 옵션','CSV 내보내기 옵션') { if (ByName $m $n) { Fail "시작 전에 이미 '$n' 창이 열려 있음" } }

# 2. 조제내역현황 화면 (열려 있고 앞에 보이면 그대로, 아니면 조제관리 메뉴 10번째 항목)
function Form { $f = ByNameType $m '조제내역현황' ([System.Windows.Automation.ControlType]::Window); if ($f -and (Rect $f).X -ge 0) { $f } }
$form = Form
if (-not $form) {
  Click 203 29   # 맨 위 메뉴 '조제관리' (메뉴줄은 이름이 안 보임: 창 왼쪽 위 고정 위치, 재고관리 왼쪽)
  $pop = WaitFor { foreach ($w in TopWins) { try { if ($w.Current.ClassName -like 'WindowsForms10.Window.20808*') { return $w } } catch {} } } 3 '조제관리 메뉴'
  $pr = Rect $pop
  if ([Math]::Abs($pr.Height - 364) -gt 30) { Click 203 29; Fail "조제관리 메뉴 크기가 예상과 다름 (높이 $($pr.Height)) — 메뉴 항목이 바뀌었을 수 있음" }
  Click ($pr.X + 70) ($pr.Y + 228)   # 10번째 항목 '조제내역현황' (항목 간격 약 24.3)
  $form = WaitFor { Form } 15 '조제내역현황 화면'
  Start-Sleep -Seconds 1
}
Log '조제내역현황 화면 찾음'

# 3. '조제약품별' 탭으로 (탭은 이름이 안 보임: 폼 왼쪽 위에서 (148, 81)). 바뀐 것은 조제약품현황 칸의 조회 단추가 보이는지로 확인.
$fr = Rect $form
Click ($fr.X + 148) ($fr.Y + 81); Start-Sleep -Milliseconds 800
$q = WaitFor { SectionBtn '조회' } 5 "'조제약품별' 탭 (조제약품현황 조회 단추)"
$p = Need (SectionBtn '출력') '조제약품현황 출력 단추'
Log '조제약품별 탭 확인'

# 4. 검색기간 빠른선택 ▼ → 최근6개월 (11번째). ▼ = 끝 날짜 칸 왼쪽 위에서 (126, 7). 목록에서 최근6개월은 ▼ 기준 (-9, 157)
$dates = @(); $c = New-Object System.Windows.Automation.PropertyCondition($A::ClassNameProperty, 'WindowsForms10.EDIT.app.0.338574f_r15_ad1')
foreach ($e in $form.FindAll($Scope::Descendants, $c)) { $r = Rect $e; if ($e.Current.Name -match '^\d{4}-\d\d-\d\d$' -and $r.Y -lt $fr.Y + 40 -and $r.Y -gt $fr.Y) { $dates += $e } }
if ($dates.Count -ne 2) { Fail "검색기간 날짜 칸 2개를 못 찾음 ($($dates.Count)개)" }
$toBox = $dates | Sort-Object { (Rect $_).X } | Select-Object -Last 1
$tr = Rect $toBox
$dx = $tr.X + 126; $dy = $tr.Y + 7
Click $dx $dy; Start-Sleep -Milliseconds 700
Click ($dx - 9) ($dy + 157)
Start-Sleep -Milliseconds 600
$from = (Get-Date).AddMonths(-6).ToString('yyyy-MM-dd'); $to = (Get-Date).ToString('yyyy-MM-dd')
if (-not (ByName $form $from) -or -not (ByName $form $to)) { Fail "검색기간이 $from ~ $to 로 안 바뀜" }
Log "검색기간 $from ~ $to"

# 5. 조제약품현황 칸의 조회 (탭을 한 번 더 확인한 뒤). 끝날 때까지 이팜이 바쁜 동안 기다림
Front
$q = Need (SectionBtn '조회') "조제약품현황 조회 단추 ('조제약품별' 탭이 아님)"
ClickEl $q
Start-Sleep -Seconds 1
try { [void](Get-Process -Id $m.Current.ProcessId).WaitForInputIdle(60000) } catch {}
Start-Sleep -Seconds 2
NoSurprise $m
Log '조회 끝'

# 6. 미리보기 켜고 출력. 미리보기 칸 = 오른쪽 큰 조회 단추(높이 40) 왼쪽 위에서 (8, 58)
$big = $null; foreach ($e in (AllByName $form '조회')) { $r = Rect $e; if ($r.Height -gt 32 -and $r.X -gt $fr.X + $fr.Width/2) { $big = $e } }
$br = Rect (Need $big '오른쪽 큰 조회 단추')
SetCheck ($br.X + 8) ($br.Y + 58) $true '미리보기'
ClickEl (Need (SectionBtn '출력') '조제약품현황 출력 단추')
$pv = WaitFor { NoSurprise $m; ByName $m '출력 미리보기' } 60 '출력 미리보기 창'
Start-Sleep -Seconds 2
$pr = Rect $pv
Log '출력 미리보기 열림'

# 7. 변환 ▼ → XLSX 파일 (6번째). 미리보기 창 왼쪽 위 기준 변환 (478,128), XLSX (534,368)
Click ($pr.X + 478) ($pr.Y + 128); Start-Sleep -Milliseconds 900
Click ($pr.X + 534) ($pr.Y + 368)
$opt = WaitFor { NoSurprise $m; ByName $m 'XLSX 내보내기 옵션' } 10 'XLSX 내보내기 옵션 창'
ClickEl (Need (ByName $opt '확인') 'XLSX 옵션 확인 단추')

# 8. 다른 이름으로 저장: 기본 이름이 '조제약품현황'인지 확인 → 임시 폴더에 저장 → 나중에 OutPath 로 옮김
$sa = WaitFor { ByName $m '다른 이름으로 저장' } 15 '다른 이름으로 저장 창'
Start-Sleep -Milliseconds 800
$fnc = New-Object System.Windows.Automation.AndCondition((New-Object System.Windows.Automation.PropertyCondition($A::AutomationIdProperty, '1001')), (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Pane)))
$fnv = $sa.FindFirst($Scope::Descendants, $fnc)
if (-not $fnv -or $fnv.Current.Name -notlike '조제약품현황*') { Fail "저장 창 기본 이름이 '조제약품현황'이 아님 (지금: '$($fnv.Current.Name)') — 다른 표가 출력됐을 수 있음" }
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('_조제저장중_' + (Get-Date -Format 'HHmmssfff') + '.xlsx')
$host1 = Need (ById $sa 'FileNameControlHost') '파일 이름 칸'
$hr = Rect $host1
Front
Click ($hr.X + 40) ($hr.Y + $hr.Height/2); Start-Sleep -Milliseconds 300
Set-Clipboard -Value $tmp
[System.Windows.Forms.SendKeys]::SendWait('^a'); Start-Sleep -Milliseconds 150
[System.Windows.Forms.SendKeys]::SendWait('^v'); Start-Sleep -Milliseconds 500
$fnv = $sa.FindFirst($Scope::Descendants, $fnc)
if (-not $fnv -or $fnv.Current.Name -ne $tmp) { Fail "파일 이름이 안 들어감 (지금: '$($fnv.Current.Name)')" }
ClickEl (Need (ByNameType $sa '저장(S)' ([System.Windows.Automation.ControlType]::Pane)) '저장(S) 단추')
Start-Sleep -Seconds 1
NoSurprise $m

# 9. "이 파일을 여시겠습니까?" → 아니오
$qq = WaitFor { ByName $m '내보내기' } 60 '내보내기 완료 질문 창'
ClickEl (Need (ByName $qq '아니오(N)') '아니오(N) 단추')
WaitGone { ByName $m '내보내기' } 5 '내보내기 질문 창'

# 10. 미리보기 닫기 (미리보기 창 왼쪽 위 기준 닫기 (735,108) — 재고현황 미리보기와 자리가 다름)
$pv = ByName $m '출력 미리보기'
if ($pv) { $pr = Rect $pv; Click ($pr.X + 735) ($pr.Y + 108); WaitGone { ByName $m '출력 미리보기' } 5 '출력 미리보기 창' }

# 11. 이팜을 '메인' 탭으로 돌려 둠 (문서 탭 줄 맨 왼쪽, 창 왼쪽 위에서 (28, 70))
$mr = Rect $m
Click ($mr.X + 28) ($mr.Y + 70); Start-Sleep -Milliseconds 500

# 12. 임시 파일 내용 확인(제목·기간·머리줄·줄 수) → OutPath
if (-not (Test-Path $tmp)) { Fail "저장된 파일이 없음: $tmp" }
$chk = $null; try { $chk = CheckXlsx $tmp } catch { Remove-Item -LiteralPath $tmp -Force; Fail "저장된 파일을 못 읽음: $_" }
$why = $null
if (-not $chk) { $why = '표 머리줄을 못 찾음' }
elseif ($chk.Top -notmatch '조제약품현황') { $why = '제목이 조제약품현황이 아님' }
elseif ($chk.Top -notmatch [regex]::Escape("${from}~${to}")) { $why = "검색기간이 $from~$to 가 아님" }
elseif (($chk.Header -join ',') -ne ($expectCols -join ',')) { $why = '열 이름이 예전 파일과 다름: ' + ($chk.Header -join ',') }
elseif ($chk.Rows -lt 100) { $why = "약품 줄 수 $($chk.Rows) — 너무 적음" }
if ($why) { Remove-Item -LiteralPath $tmp -Force; Fail $why }
Move-Item -LiteralPath $tmp -Destination $OutPath -Force
$fi = Get-Item -LiteralPath $OutPath
if (((Get-Date) - $fi.LastWriteTime).TotalSeconds -gt 120) { Fail '파일 시각이 2분보다 오래됨' }
Log "성공: $OutPath ($([int]($fi.Length/1KB))KB, 약품 $($chk.Rows)줄)"
exit 0
