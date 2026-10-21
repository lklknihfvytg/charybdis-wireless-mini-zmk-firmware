param([ValidateRange(1, 300)][int]$Seconds = 30, [switch]$CompareDevices, [switch]$ValidateOnly)
$ErrorActionPreference = 'Stop'
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public sealed class PointerTestStatus : Form {
    public readonly Label Status = new Label();
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { CreateParams parameters = base.CreateParams; parameters.ExStyle |= 0x08000000; return parameters; }
    }
    public PointerTestStatus() {
        Text="Pointer comparison"; TopMost=true; ShowInTaskbar=false;
        FormBorderStyle=FormBorderStyle.FixedToolWindow;
        StartPosition=FormStartPosition.Manual;
        ClientSize=new System.Drawing.Size(390,100);
        System.Drawing.Rectangle screen=Screen.PrimaryScreen.WorkingArea;
        Location=new System.Drawing.Point(screen.Right-ClientSize.Width-20,screen.Top+20);
        Status.Dock=DockStyle.Fill; Status.TextAlign=System.Drawing.ContentAlignment.MiddleCenter;
        Status.Font=new System.Drawing.Font("Segoe UI",13);
        Controls.Add(Status);
    }
}

public sealed class PointerMeasurement : NativeWindow {
    [StructLayout(LayoutKind.Sequential)] struct Device {
        public ushort page, usage; public uint flags; public IntPtr target;
    }
    [StructLayout(LayoutKind.Sequential)] struct Header {
        public uint type, size; public IntPtr device, param;
    }
    [StructLayout(LayoutKind.Sequential)] struct Message {
        public IntPtr hwnd; public uint message; public UIntPtr wParam;
        public IntPtr lParam; public uint time; public int x, y; public uint extra;
    }
    sealed class Sample {
        public double ms; public IntPtr device; public int x, y; public ushort flags, buttons;
    }
    [DllImport("user32.dll", SetLastError=true)] static extern bool RegisterRawInputDevices(Device[] devices, uint count, uint size);
    [DllImport("user32.dll", SetLastError=true)] static extern uint GetRawInputData(IntPtr input, uint command, IntPtr data, ref uint size, uint header);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern uint GetRawInputDeviceInfo(IntPtr device, uint command, StringBuilder data, ref uint size);
    [DllImport("user32.dll")] static extern int GetMessage(out Message message, IntPtr hwnd, uint min, uint max);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref Message message);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref Message message);
    [DllImport("user32.dll", SetLastError=true)] static extern UIntPtr SetTimer(IntPtr hwnd, UIntPtr id, uint ms, IntPtr callback);
    [DllImport("user32.dll")] static extern bool KillTimer(IntPtr hwnd, UIntPtr id);
    [DllImport("user32.dll", SetLastError=true)] static extern bool SystemParametersInfo(uint action, uint param, out int value, uint flags);
    readonly Stopwatch clock = new Stopwatch();
    readonly List<Sample> samples = new List<Sample>();
    readonly IntPtr buffer = Marshal.AllocHGlobal(1024);
    readonly uint headerSize = (uint)Marshal.SizeOf(typeof(Header));
    protected override void WndProc(ref System.Windows.Forms.Message m) {
        if (m.Msg == 0x00FF && clock.IsRunning) {
            uint size = 1024;
            uint read = GetRawInputData(m.LParam, 0x10000003, buffer, ref size, headerSize);
            if (read != UInt32.MaxValue && read >= headerSize + 24) {
                Header header = (Header)Marshal.PtrToStructure(buffer, typeof(Header));
                if (header.type == 0) {
                    int offset = (int)headerSize;
                    samples.Add(new Sample {ms=clock.Elapsed.TotalMilliseconds, device=header.device,
                        x=Marshal.ReadInt32(buffer, offset+12), y=Marshal.ReadInt32(buffer, offset+16),
                        flags=(ushort)Marshal.ReadInt16(buffer, offset),
                        buttons=(ushort)Marshal.ReadInt16(buffer, offset+4)});
                }
            }
        }
        base.WndProc(ref m);
    }
    static string Name(IntPtr device) {
        uint size=0;
        GetRawInputDeviceInfo(device, 0x20000007, null, ref size);
        if (size==0) return device.ToInt64().ToString("X");
        StringBuilder name = new StringBuilder((int)size+1);
        return GetRawInputDeviceInfo(device, 0x20000007, name, ref size)==UInt32.MaxValue
            ? device.ToInt64().ToString("X") : name.ToString();
    }
    public static double Run(int seconds, string path, bool compare) {
        PointerMeasurement capture = new PointerMeasurement();
        PointerTestStatus status=null;
        bool registered=false;
        UIntPtr timer=UIntPtr.Zero;
        try {
            CreateParams creation = new CreateParams();
            creation.Caption="Pointer measurement";
            creation.Parent=new IntPtr(-3); // Message-only window; does not take focus.
            capture.CreateHandle(creation);
            Device device = new Device {page=1, usage=2, flags=0x100, target=capture.Handle};
            if (!RegisterRawInputDevices(new Device[]{device},1,(uint)Marshal.SizeOf(typeof(Device))))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            registered=true;
            timer=SetTimer(capture.Handle,new UIntPtr(1),100,IntPtr.Zero);
            if (timer==UIntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            int vanish;
            if (!SystemParametersInfo(0x1020,0,out vanish,0))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            Console.WriteLine("Windows HidePointerWhileTyping="+(vanish!=0));
            if(compare) {
                seconds=50;
                status=new PointerTestStatus();
                status.Status.Text="GET READY: TRACKBALL in 5 seconds";
                status.Show();
                Console.WriteLine("Follow the panel: 5s preparation, 20s TRACKBALL, 5s switch, 20s MOUSE.");
            } else {
                Console.WriteLine("START: move trackball continuously. At 15 seconds, also type.");
            }
            capture.clock.Start();
            bool phasePrinted=false;
            Message message;
            while (capture.clock.Elapsed.TotalSeconds < seconds) {
                int result=GetMessage(out message,IntPtr.Zero,0,0);
                if (result==-1) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                if (result==0) break;
                TranslateMessage(ref message);
                DispatchMessage(ref message);
                if(compare) {
                    if(status.IsDisposed) break;
                    double elapsed=capture.clock.Elapsed.TotalSeconds;
                    if(elapsed<5) status.Status.Text="GET READY: TRACKBALL in "+Math.Ceiling(5-elapsed)+"s";
                    else if(elapsed<25) status.Status.Text="TRACKBALL ONLY: keep circling\n"+Math.Ceiling(25-elapsed)+" seconds left";
                    else if(elapsed<30) status.Status.Text="SWITCH TO WIRED MOUSE\nStart in "+Math.Ceiling(30-elapsed)+"s";
                    else status.Status.Text="WIRED MOUSE ONLY: keep circling\n"+Math.Ceiling(50-elapsed)+" seconds left";
                } else if (!phasePrinted && capture.clock.Elapsed.TotalSeconds>=15) {
                    Console.WriteLine("SECOND PHASE: keep moving the trackball and type.");
                    phasePrinted=true;
                }
            }
            capture.clock.Stop();
            Dictionary<IntPtr,string> names=new Dictionary<IntPtr,string>();
            using (StreamWriter output=new StreamWriter(path,false,Encoding.UTF8)) {
                output.WriteLine("elapsed_ms,device,dx,dy,flags,buttons");
                foreach (Sample sample in capture.samples) {
                    if (!names.ContainsKey(sample.device)) names[sample.device]=Name(sample.device);
                    output.WriteLine(sample.ms.ToString("F4",CultureInfo.InvariantCulture)+",\""+
                        names[sample.device].Replace("\"","\"\"")+"\","+sample.x+","+sample.y+","+sample.flags+","+sample.buttons);
                }
            }
            Console.WriteLine("Saved "+capture.samples.Count+" mouse events: "+path);
            foreach (string name in names.Values) Console.WriteLine("Device: "+name);
            return capture.clock.Elapsed.TotalSeconds;
        } finally {
            if(status!=null) status.Dispose();
            if (registered) RegisterRawInputDevices(new Device[]{new Device{page=1,usage=2,flags=1,target=IntPtr.Zero}},1,(uint)Marshal.SizeOf(typeof(Device)));
            if (timer!=UIntPtr.Zero) KillTimer(capture.Handle,timer);
            capture.DestroyHandle();
            Marshal.FreeHGlobal(capture.buffer);
        }
    }
}
'@
if ($ValidateOnly) { Write-Output 'Pointer capture compiled; no recording started.'; exit 0 }
$logDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'build\logs'
New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
$logPath = Join-Path $logDirectory ('pointer-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')
$elapsed = [PointerMeasurement]::Run($Seconds, $logPath, $CompareDevices.IsPresent)
if ($CompareDevices) {
    @{
        mode = 'trackball-vs-wired-mouse'
        elapsed_seconds = $elapsed
        completed = ($elapsed -ge 50)
        phases = @(
            @{ label = 'trackball'; start_seconds = 5; end_seconds = 25 },
            @{ label = 'wired_mouse'; start_seconds = 30; end_seconds = 50 }
        )
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath ($logPath + '.phases.json') -Encoding UTF8
}
