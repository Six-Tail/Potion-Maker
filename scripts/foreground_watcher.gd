extends Node
## Windows 포그라운드(최상위) 창을 감지하는 싱글턴(Watcher).
##
## GDScript 만으로는 다른 창의 정보를 알 수 없으므로,
## 백그라운드에서 PowerShell 헬퍼를 (콘솔창 없이 wscript 로) 실행해
## 현재 최상위 창의 "HWND<<>>프로세스명<<>>제목" 을 user://foreground.txt 에
## 계속 기록하게 하고, Godot 이 이를 주기적으로 읽는다.

signal foreground_updated(pname: String, title: String)

const POLL_INTERVAL := 0.3
const STALE_AFTER := 3.0
const SEP := "<<>>"

var self_hwnd: int = 0
var online: bool = false

# 현재 최상위 창
var cur_hwnd: int = 0
var cur_name: String = ""
var cur_title: String = ""

# 우리 위젯이 아닌 마지막 외부 창 (설정의 "추가" 버튼이 사용)
var last_external_name: String = ""
var last_external_title: String = ""

var _last_ok_time: float = 0.0
var _data_dir: String = ""
var _fg_path: String = ""
var _launched: bool = false

func _ready() -> void:
	self_hwnd = _get_self_hwnd()
	_data_dir = OS.get_user_data_dir()
	_fg_path = "user://foreground.txt"
	if OS.get_name() == "Windows":
		_write_helper_scripts()
		_launch_helper()
	var t := Timer.new()
	t.wait_time = POLL_INTERVAL
	t.autostart = true
	t.timeout.connect(_poll)
	add_child(t)

func _get_self_hwnd() -> int:
	# Windows 에서 창의 네이티브 핸들(HWND)을 반환.
	if DisplayServer.has_method("window_get_native_handle"):
		return DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	return 0

## 현재 PC 를 "사용 중"으로 볼지 판정.
func is_pc_active() -> bool:
	if GameState.force_active:
		return true
	if not online:
		return false
	return GameState.is_app_registered(cur_name)

func status_text() -> String:
	if OS.get_name() != "Windows":
		return "감지기: Windows 전용 (테스트 모드 사용)"
	if GameState.force_active:
		return "감지기: 강제 진행 ON"
	if not online:
		return "감지기: 오프라인 (헬퍼 시작 대기)"
	if GameState.registered_apps.is_empty():
		return "감지기: 온라인 · 등록된 앱 없음"
	if GameState.is_app_registered(cur_name):
		return "감지 중: %s (사용 중)" % _display(cur_name, cur_title)
	return "감지 중: %s (대기)" % _display(cur_name, cur_title)

func _display(pname: String, title: String) -> String:
	if pname == "":
		return "(알 수 없음)"
	if title.strip_edges() != "":
		return "%s — %s" % [pname, title]
	return pname

# ---------- 폴링 ----------
func _poll() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not FileAccess.file_exists(_fg_path):
		if now - _last_ok_time > STALE_AFTER:
			online = false
		return
	var f := FileAccess.open(_fg_path, FileAccess.READ)
	if f == null:
		return
	var line := f.get_as_text()
	f.close()
	line = line.replace("\ufeff", "").strip_edges()
	if line == "":
		return
	var parts := line.split(SEP, false)
	var hwnd := 0
	var pname := ""
	var title := ""
	if parts.size() >= 1:
		hwnd = int(parts[0])
	if parts.size() >= 2:
		pname = parts[1].strip_edges()
	if parts.size() >= 3:
		title = parts[2].strip_edges()

	online = true
	_last_ok_time = now
	cur_hwnd = hwnd
	cur_name = pname
	cur_title = title

	# 우리 위젯이 아닌 외부 창이면 "마지막 외부 창"으로 기록
	if hwnd != self_hwnd and pname != "":
		last_external_name = pname
		last_external_title = title

	foreground_updated.emit(pname, title)

# ---------- 헬퍼 실행 ----------
func _launch_helper() -> void:
	if _launched:
		return
	var wscript := "C:/Windows/System32/wscript.exe"
	var vbs := _data_dir + "/watcher.vbs"
	var ps1 := _data_dir + "/watcher.ps1"
	var gpid := OS.get_process_id()
	# watcher.stop 플래그가 남아있으면 제거
	if FileAccess.file_exists("user://watcher.stop"):
		DirAccess.remove_absolute(_data_dir + "/watcher.stop")
	var args := [vbs, ps1, _data_dir, str(gpid)]
	var pid := OS.create_process(wscript, args)
	_launched = pid != -1

func _exit_tree() -> void:
	stop_helper()

func stop_helper() -> void:
	# 헬퍼에게 종료 신호(파일) 전달. 헬퍼는 이 파일을 보면 스스로 종료한다.
	var f := FileAccess.open("user://watcher.stop", FileAccess.WRITE)
	if f:
		f.store_string("stop")
		f.close()

func _write_helper_scripts() -> void:
	_write_text("user://watcher.ps1", _ps1_source())
	_write_text("user://watcher.vbs", _vbs_source())
	_write_text("user://notify.ps1", _notify_ps1_source())
	_write_text("user://notify.vbs", _notify_vbs_source())

func _write_text(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()

## Windows 알림(토스트) 표시. 제목/내용을 파일로 넘겨 인코딩 문제를 피한다.
func notify(title: String, message: String) -> void:
	if OS.get_name() != "Windows":
		return
	var f := FileAccess.open("user://notify.txt", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(title + "\n" + message)
	f.close()
	var wscript := "C:/Windows/System32/wscript.exe"
	var vbs := _data_dir + "/notify.vbs"
	var ps1 := _data_dir + "/notify.ps1"
	OS.create_process(wscript, [vbs, ps1, _data_dir])

func _ps1_source() -> String:
	# 주의: 이 문자열 안에는 역슬래시를 넣지 않는다(GDScript 이스케이프 회피).
	return """param([string]$DataDir, [int]$GodotPid)
$src = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class FG {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr hWnd, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder s, int n);
  public static string Info() {
    IntPtr h = GetForegroundWindow();
    int pid; GetWindowThreadProcessId(h, out pid);
    string name = "";
    try { name = System.Diagnostics.Process.GetProcessById(pid).ProcessName; } catch {}
    StringBuilder sb = new StringBuilder(512);
    GetWindowText(h, sb, 512);
    return ((long)h).ToString() + "<<>>" + name + "<<>>" + sb.ToString();
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp
$enc = New-Object System.Text.UTF8Encoding($false)
$out = Join-Path $DataDir "foreground.txt"
$stop = Join-Path $DataDir "watcher.stop"
if (Test-Path $stop) { Remove-Item $stop -Force -ErrorAction SilentlyContinue }
while ($true) {
  try {
    $info = [FG]::Info()
    [System.IO.File]::WriteAllText($out, $info, $enc)
  } catch {}
  if (Test-Path $stop) { break }
  if (-not (Get-Process -Id $GodotPid -ErrorAction SilentlyContinue)) { break }
  Start-Sleep -Milliseconds 400
}
"""

func _vbs_source() -> String:
	# 따옴표는 Chr(34) 로 조립해 GDScript 삼중따옴표와 충돌하지 않게 한다.
	return """Set sh = CreateObject("WScript.Shell")
q = Chr(34)
ps1 = WScript.Arguments(0)
dataDir = WScript.Arguments(1)
gpid = WScript.Arguments(2)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & q & ps1 & q & " -DataDir " & q & dataDir & q & " -GodotPid " & gpid
sh.Run cmd, 0, False
"""

func _notify_ps1_source() -> String:
	return """param([string]$DataDir)
$f = Join-Path $DataDir "notify.txt"
if (-not (Test-Path $f)) { return }
$lines = @(Get-Content -Path $f -Encoding UTF8)
$title = "Potion Workshop"
$msg = ""
if ($lines.Count -ge 1) { $title = $lines[0] }
if ($lines.Count -ge 2) { $msg = $lines[1] }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$n = New-Object System.Windows.Forms.NotifyIcon
$n.Icon = [System.Drawing.SystemIcons]::Information
$n.Visible = $true
$n.ShowBalloonTip(6000, $title, $msg, [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 7
$n.Visible = $false
$n.Dispose()
"""

func _notify_vbs_source() -> String:
	return """Set sh = CreateObject("WScript.Shell")
q = Chr(34)
ps1 = WScript.Arguments(0)
dataDir = WScript.Arguments(1)
cmd = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & q & ps1 & q & " -DataDir " & q & dataDir & q
sh.Run cmd, 0, False
"""
