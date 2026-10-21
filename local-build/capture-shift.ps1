param([ValidateRange(1,300)][int]$Seconds = 60, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class ShiftCapture : NativeWindow {
    [StructLayout(LayoutKind.Sequential)] struct Device { public ushort page, usage; public uint flags; public IntPtr target; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public uint type, size; public IntPtr device, param; }
    [StructLayout(LayoutKind.Sequential)] struct NativeMessage { public IntPtr hwnd; public uint message; public UIntPtr wParam; public IntPtr lParam; public uint time; public int x,y; public uint extra; }
    [StructLayout(LayoutKind.Sequential)] struct Sticky { public uint size, flags; }
    [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterRawInputDevices(Device[] data,uint count,uint size);
    [DllImport("user32.dll",SetLastError=true)] static extern uint GetRawInputData(IntPtr input,uint command,IntPtr data,ref uint size,uint header);
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern uint GetRawInputDeviceInfo(IntPtr device,uint command,StringBuilder data,ref uint size);
    [DllImport("user32.dll")] static extern int GetMessage(out NativeMessage message,IntPtr hwnd,uint min,uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref NativeMessage message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref NativeMessage message);
    [DllImport("user32.dll")] static extern UIntPtr SetTimer(IntPtr hwnd,UIntPtr id,uint ms,IntPtr callback);
    [DllImport("user32.dll")] static extern bool KillTimer(IntPtr hwnd,UIntPtr id);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern short GetKeyState(int key);
    [DllImport("user32.dll",SetLastError=true)] static extern bool SystemParametersInfo(uint action,uint param,ref Sticky value,uint flags);
    readonly Stopwatch clock=new Stopwatch();
    readonly List<string> rows=new List<string>();
    readonly Dictionary<IntPtr,string> names=new Dictionary<IntPtr,string>();
    readonly IntPtr buffer=Marshal.AllocHGlobal(1024);
    readonly uint headerSize=(uint)Marshal.SizeOf(typeof(Header));
    string previousState="";
    int otherPresses;
    static string Name(IntPtr handle) {
        uint size=0; GetRawInputDeviceInfo(handle,0x20000007,null,ref size);
        if(size==0) return handle.ToInt64().ToString("X");
        StringBuilder text=new StringBuilder((int)size+1);
        return GetRawInputDeviceInfo(handle,0x20000007,text,ref size)==UInt32.MaxValue ? handle.ToInt64().ToString("X") : text.ToString();
    }
    static bool Down(int key) { return (GetAsyncKeyState(key)&0x8000)!=0; }
    string State() {
        Sticky sticky=new Sticky {size=(uint)Marshal.SizeOf(typeof(Sticky))};
        if(!SystemParametersInfo(0x003A,sticky.size,ref sticky,0)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return "LS="+Down(0xA0)+";RS="+Down(0xA1)+";CTRL="+Down(0x11)+";ALT="+Down(0x12)+";CAPS="+((GetKeyState(0x14)&1)!=0)+";STICKY=0x"+sticky.flags.ToString("X");
    }
    void Add(string kind,string device,string key,string state,string flags) {
        rows.Add(clock.Elapsed.TotalMilliseconds.ToString("F3",CultureInfo.InvariantCulture)+",\""+kind+"\",\""+device.Replace("\"","\"\"")+"\",\""+key+"\",\""+state+"\",\""+flags+"\"");
    }
    protected override void WndProc(ref System.Windows.Forms.Message m) {
        if(clock.IsRunning && m.Msg==0x00FF) {
            uint size=1024;
            uint read=GetRawInputData(m.LParam,0x10000003,buffer,ref size,headerSize);
            if(read!=UInt32.MaxValue && read>=headerSize+16) {
                Header header=(Header)Marshal.PtrToStructure(buffer,typeof(Header));
                if(header.type==1) {
                    int offset=(int)headerSize;
                    ushort scan=(ushort)Marshal.ReadInt16(buffer,offset);
                    ushort flags=(ushort)Marshal.ReadInt16(buffer,offset+2);
                    ushort key=(ushort)Marshal.ReadInt16(buffer,offset+6);
                    bool released=(flags&1)!=0;
                    string label=null;
                    if(key==0x10 || key==0xA0 || key==0xA1) label=scan==0x36 ? "RSHIFT" : "LSHIFT";
                    else if(key==0x7C) label="F13";
                    else if(key==0x7D) label="F14";
                    if(label!=null) {
                        if(!names.ContainsKey(header.device)) names[header.device]=Name(header.device);
                        Add("raw",names[header.device],label,released ? "up" : "down","0x"+flags.ToString("X"));
                    } else if(!released) otherPresses++;
                }
            }
        }
        if(clock.IsRunning && m.Msg==0x0113) {
            string state=State();
            if(state!=previousState) { Add("windows","","",state,""); previousState=state; }
        }
        base.WndProc(ref m);
    }
    public static void Run(int seconds,string path) {
        ShiftCapture capture=new ShiftCapture(); bool registered=false; UIntPtr timer=UIntPtr.Zero;
        try {
            capture.CreateHandle(new CreateParams {Caption="Shift diagnostics",Parent=new IntPtr(-3)});
            if(!RegisterRawInputDevices(new Device[]{new Device {page=1,usage=6,flags=0x100,target=capture.Handle}},1,(uint)Marshal.SizeOf(typeof(Device))))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            registered=true;
            timer=SetTimer(capture.Handle,new UIntPtr(1),50,IntPtr.Zero);
            if(timer==UIntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            capture.clock.Start(); capture.previousState=capture.State(); capture.Add("windows","","",capture.previousState,"");
            Console.WriteLine("START: type normally for "+seconds+" seconds. If Shift sticks, release all keys for 2-3 seconds, then recover with D.");
            NativeMessage message;
            while(capture.clock.Elapsed.TotalSeconds<seconds) {
                int result=GetMessage(out message,IntPtr.Zero,0,0);
                if(result<0) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                if(result==0) break;
                TranslateMessage(ref message); DispatchMessage(ref message);
            }
            capture.Add("windows-final","","",capture.State(),"");
            capture.clock.Stop();
            using(StreamWriter output=new StreamWriter(path,false,Encoding.UTF8)) {
                output.WriteLine("elapsed_ms,kind,device,key,state,flags");
                foreach(string row in capture.rows) output.WriteLine(row);
            }
            Console.WriteLine("DONE. Other key presses counted without retaining key codes: "+capture.otherPresses);
            Console.WriteLine(path);
        } finally {
            if(timer!=UIntPtr.Zero) KillTimer(capture.Handle,timer);
            if(registered) RegisterRawInputDevices(new Device[]{new Device {page=1,usage=6,flags=1,target=IntPtr.Zero}},1,(uint)Marshal.SizeOf(typeof(Device)));
            capture.DestroyHandle(); Marshal.FreeHGlobal(capture.buffer);
        }
    }
}
'@
if ($ValidateOnly) { Write-Output 'Shift capture compiled; no capture started.'; exit 0 }
$logDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'build/logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$outputPath = Join-Path $logDir ('shift-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')
[ShiftCapture]::Run($Seconds, $outputPath)
