# 이팜 자동 저장 공통 도우미: 중간에 뜬 알림창 닫기 · 다른 창이 가리면 기다리기 · 멈출 때 열린 창 정리
# ipam_stock.ps1 / ipam_disp.ps1 가 Log·ByName·ByNameType·TopWins 를 만든 뒤 점(.)으로 불러 씀. 쓰는 변수: $m(이팜 본창) $h(본창 핸들)
# 끝내기 코드: 0 성공 · 1 멈춤(다시 해도 같을 것) · 2 다른 창·알림창 때문에 멈춤 → PC 약국비서가 한 번 더 해 봄
# 알림창 처리 원칙: '예'는 절대 누르지 않음. 아니오 → (확인·취소 질문이면) 취소 → 닫기 → 확인(확인 하나뿐인 안내창) 순서. 취소만 있는 진행 창은 그대로 둠.
Add-Type @"
using System; using System.Text; using System.Runtime.InteropServices;
public class EG {
 [StructLayout(LayoutKind.Sequential)] public struct PT { public int X; public int Y; }
 [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(PT p);
 [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h,int f);
 [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h,out int pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h,int m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void keybd_event(byte k,byte s,int f,int e);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(int f,int x,int y,int d,int e);
}
"@
# 이번 작업이 일부러 여는 창 (알림창으로 보고 닫으면 안 됨)
$script:expectWins = @('출력 미리보기','다른 이름으로 저장','XLSX 내보내기 옵션','내보내기')
# NoSurprise 가 따로 맡는 질문 창
$script:askWins = @('초기화 하시겠습니까 ?','다른 이름으로 저장 확인','CSV 내보내기 옵션')
$script:dismissBtns = @('아니오(N)','아니요(N)','아니오','아니요','취소','닫기','확인')
$script:popCount = 0
$script:epPidV = 0
$script:cleaning = $false

function Fail($msg) { Log ('실패: ' + $msg); Cleanup; exit 1 }
function Retry($msg) { Log ('실패: ' + $msg); Cleanup; exit 2 }
function EpPid { if (-not $script:epPidV -and $m) { try { $script:epPidV = $m.Current.ProcessId } catch {} }; $script:epPidV }
function RawClick($x, $y) { [void][EG]::SetCursorPos([int]$x, [int]$y); Start-Sleep -Milliseconds 150; [EG]::mouse_event(2,0,0,0,0); Start-Sleep -Milliseconds 60; [EG]::mouse_event(4,0,0,0,0) }
function ClickCenter($el) { $r = $el.Current.BoundingRectangle; RawClick ($r.X + $r.Width/2) ($r.Y + $r.Height/2) }

# (x,y) 자리에 맨 위로 보이는 창: 핸들·프로그램·제목
function WinAt($x, $y) {
  $p = New-Object EG+PT; $p.X = [int]$x; $p.Y = [int]$y
  $r = [EG]::GetAncestor([EG]::WindowFromPoint($p), 2)
  $wpid = 0; [void][EG]::GetWindowThreadProcessId($r, [ref]$wpid)
  $sb = New-Object System.Text.StringBuilder 256; [void][EG]::GetWindowText($r, $sb, 256)
  $pn = ''; try { $pn = (Get-Process -Id $wpid -ErrorAction Stop).ProcessName } catch {}
  [pscustomobject]@{ H = $r; Pid = $wpid; Title = $sb.ToString(); Proc = $pn }
}
function WinLabel($o) { if ($o.Title) { "'$($o.Title)'" } elseif ($o.Proc) { "'$($o.Proc)' 프로그램" } else { '알 수 없는' } }

# 이팜(또는 이팜이 띄운 창)이 맨 앞인지 확인. 아니면 Alt 한 번 누른 뒤 다시 앞으로 (윈도우가 앞으로 가져오기를 막을 때)
function Front {
  for ($k = 0; $k -lt 4; $k++) {
    $fg = [EG]::GetForegroundWindow(); $fpid = 0; [void][EG]::GetWindowThreadProcessId($fg, [ref]$fpid)
    if ($fpid -eq (EpPid)) { return }
    if ($k -ge 1) { [EG]::keybd_event(0x12,0,0,0); [EG]::keybd_event(0x12,0,2,0); Start-Sleep -Milliseconds 100 }
    [void][EG]::SetForegroundWindow($h); Start-Sleep -Milliseconds 600
  }
  $fg = [EG]::GetForegroundWindow(); $fpid = 0; [void][EG]::GetWindowThreadProcessId($fg, [ref]$fpid)
  if ($fpid -ne (EpPid)) {
    $sb = New-Object System.Text.StringBuilder 256; [void][EG]::GetWindowText($fg, $sb, 256)
    $pn = ''; try { $pn = (Get-Process -Id $fpid -ErrorAction Stop).ProcessName } catch {}
    Retry ("이팜 창을 맨 앞으로 못 가져옴 — " + (WinLabel ([pscustomobject]@{ Title = $sb.ToString(); Proc = $pn })) + ' 창이 앞에 있음')
  }
}

# 이팜이 띄운 예상 못 한 알림창(작은 창 + 확인·아니오·취소·닫기 단추)을 찾아 닫음. 닫았으면 $true
function Popups {
  if (-not $m -or $script:cleaning) { return $false }
  $cands = @()
  try { foreach ($w in $m.FindAll($Scope::Children, (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)))) { $cands += $w } } catch {}
  try { foreach ($w in TopWins) { try { if ($w.Current.ProcessId -eq (EpPid) -and [IntPtr]$w.Current.NativeWindowHandle -ne $h) { $cands += $w } } catch {} } } catch {}
  $did = $false
  foreach ($w in $cands) {
    try {
      $nm = [string]$w.Current.Name
      if ($script:expectWins -contains $nm -or $script:askWins -contains $nm -or $nm -like '이팜 (Ver*' -or $nm -like '*쉬운폼*') { continue }
      $r = $w.Current.BoundingRectangle
      if ($w.Current.IsOffscreen -or $r.Width -lt 80 -or $r.Width -gt 900 -or $r.Height -gt 700) { continue }
      $all = $w.FindAll($Scope::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
      if ($all.Count -gt 40) { continue }   # 큰 화면(조회 화면 등)은 알림창이 아님
      $names = @(); foreach ($e in $all) { $t = [string]$e.Current.Name; if ($t) { $names += $t } }
      if ($names | Where-Object { $script:askWins -contains $_ }) { continue }
      if ($w.FindFirst($Scope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($A::ControlTypeProperty, [System.Windows.Automation.ControlType]::ProgressBar)))) { continue }  # 진행 중 창은 그대로
      # 누를 단추: 아니오 > (확인·취소 둘 다 있으면 질문이므로) 취소 > 닫기 > 확인. 취소만 있는 창(내보내는 중 등)은 건드리지 않음
      $no = $null; foreach ($b in '아니오(N)','아니요(N)','아니오','아니요') { $no = ByName $w $b; if ($no) { break } }
      $cancel = ByName $w '취소'; $close = ByName $w '닫기'; $okb = ByName $w '확인'
      $btn = if ($no) { $no } elseif ($cancel -and $okb) { $cancel } elseif ($close) { $close } elseif ($okb -and -not $cancel) { $okb } else { $null }
      if (-not $btn) { continue }
      $bname = $btn.Current.Name
      $text = (($names | Where-Object { $_ -ne $nm -and $script:dismissBtns -notcontains $_ -and $_ -notmatch '^(예|예\(Y\))$' }) -join ' ')
      if ($text.Length -gt 120) { $text = $text.Substring(0, 120) + '…' }
      $script:popCount++
      if ($script:popCount -gt 6) { Retry '이팜 알림창이 계속 떠서 멈췄어요' }
      Log "알림창 닫음: '$nm' $text → '$bname'"
      ClickCenter $btn
      $t = (Get-Date).AddSeconds(3)
      while ((Get-Date) -lt $t) { Start-Sleep -Milliseconds 300; try { if ($w.Current.IsOffscreen) { break } } catch { break } }
      $did = $true
    } catch {}
  }
  $did
}

# (x,y)를 누르기 전에: 이팜 알림창은 닫고, 다른 프로그램 창이 가리고 있으면 사라질 때까지(최대 20초) 기다림
function ClearWay($x, $y) {
  $t = (Get-Date).AddSeconds(20); $told = $false
  while ($true) {
    [void](Popups)
    $o = WinAt $x $y
    if ($o.Pid -eq (EpPid)) { if ($told) { Log '가리던 창이 사라짐 — 계속' }; return }
    if (-not $told) { Log ("다른 창이 이팜을 가림: " + (WinLabel $o) + " — 사라질 때까지 기다림"); $told = $true }
    if ((Get-Date) -gt $t) { Retry ((WinLabel $o) + ' 창이 이팜 화면을 가려서 멈췄어요') }
    [void][EG]::SetForegroundWindow($h)
    Start-Sleep -Milliseconds 700
  }
}
function Click($x, $y) { ClearWay $x $y; RawClick $x $y }

# 이름 있는 단추 누르기: 위치가 0.4초 동안 그대로인지, 그 자리에 실제로 그 단추가 있는지 확인한 뒤 누름
function ClickEl($el) {
  $name = $el.Current.Name; $x = 0; $y = 0
  for ($k = 0; $k -lt 12; $k++) {
    [void](Popups)
    $r1 = $el.Current.BoundingRectangle; Start-Sleep -Milliseconds 400; $r2 = $el.Current.BoundingRectangle
    $x = [int]($r2.X + $r2.Width/2); $y = [int]($r2.Y + $r2.Height/2)
    if ($r1 -eq $r2 -and -not $el.Current.IsOffscreen -and $r2.Width -gt 0) {
      ClearWay $x $y
      [void][EG]::SetCursorPos($x, $y); Start-Sleep -Milliseconds 200
      $at = $null; try { $at = $A::FromPoint((New-Object System.Windows.Point($x, $y))) } catch {}
      $ok = $false; $e = $at
      for ($u = 0; $e -and $u -lt 4; $u++) { if ($e.Current.Name -eq $name) { $ok = $true; break }; $e = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($e) }
      if ($ok) { Log "누름 '$name' ($x,$y)"; RawClick $x $y; return }
    }
    if ($k -eq 5) { Front }
    Start-Sleep -Milliseconds 500
  }
  $o = WinAt $x $y
  Retry ("이팜의 '$name' 단추를 못 눌렀어요 (그 자리에 " + (WinLabel $o) + " 창)")
}

# 몇 초까지 기다리며 찾기 (기다리는 동안 이팜 알림창이 뜨면 닫음)
function WaitFor([scriptblock]$find, $sec, $what) {
  $t = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $t) { $e = & $find; if ($e) { return $e }; [void](Popups); Start-Sleep -Milliseconds 300 }
  Retry "$what 이(가) ${sec}초 안에 안 나타남"
}
function WaitGone([scriptblock]$find, $sec, $what) {
  $t = (Get-Date).AddSeconds($sec)
  while ((Get-Date) -lt $t) { if (-not (& $find)) { return }; Start-Sleep -Milliseconds 300 }
  Retry "$what 이(가) ${sec}초 안에 안 닫힘"
}

# 창 닫기 (WM_CLOSE = 창의 X 단추와 같음: 저장 창은 취소, 미리보기는 닫힘). 이팜 본창은 절대 안 닫음
function CloseWin($el) {
  $e = $el
  for ($u = 0; $e -and $u -lt 5; $u++) {
    $hw = [IntPtr]$e.Current.NativeWindowHandle
    if ($hw -ne [IntPtr]::Zero) { if ($hw -eq $h) { return $false }; [void][EG]::PostMessage($hw, 0x10, [IntPtr]::Zero, [IntPtr]::Zero); return $true }
    $e = [System.Windows.Automation.TreeWalker]::RawViewWalker.GetParent($e)
  }
  $false
}
# 이번 작업이 열어 둔 창(저장·옵션·미리보기)이 남아 있는지
function LeftOpen { foreach ($n in $script:expectWins + @('다른 이름으로 저장 확인','CSV 내보내기 옵션')) { if (ByName $m $n) { return $n } }; $null }
# 멈출 때 이팜을 처음 상태 가깝게 돌려 둠: 질문 창은 아니오, 저장·옵션·미리보기 창은 닫음 (다음 번 단추가 바로 되게)
function Cleanup {
  if (-not $m -or $script:cleaning) { return }
  $script:cleaning = $true
  try {
    for ($round = 0; $round -lt 3; $round++) {
      $any = $false
      foreach ($n in '다른 이름으로 저장 확인','내보내기') {
        $d = ByNameType $m $n ([System.Windows.Automation.ControlType]::Window)
        if ($d) { foreach ($b in '아니오(N)','아니요(N)','아니오','취소') { $no = ByName $d $b; if ($no) { ClickCenter $no; $any = $true; Start-Sleep -Milliseconds 700; break } } }
      }
      foreach ($n in '다른 이름으로 저장','XLSX 내보내기 옵션','CSV 내보내기 옵션','출력 미리보기') {
        $d = ByNameType $m $n ([System.Windows.Automation.ControlType]::Window)
        if ($d -and (CloseWin $d)) { $any = $true; Start-Sleep -Milliseconds 900 }
      }
      if (-not $any) { break }
      Log "정리: 열려 있던 창 닫음 ($($round + 1))"
    }
  } catch {}
  $script:cleaning = $false
}
