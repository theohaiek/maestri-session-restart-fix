using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class MsrfNative
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct ProcessEntry
    {
        public uint Size;
        public uint Usage;
        public uint ProcessId;
        public IntPtr DefaultHeapId;
        public uint ModuleId;
        public uint Threads;
        public uint ParentProcessId;
        public int PriorityClassBase;
        public uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string ExeFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ProcessBasicInformation
    {
        public IntPtr Reserved1;
        public IntPtr PebBaseAddress;
        public IntPtr Reserved2a;
        public IntPtr Reserved2b;
        public IntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool Process32FirstW(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool Process32NextW(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("ntdll.dll")]
    static extern int NtQueryInformationProcess(IntPtr process, int infoClass, ref ProcessBasicInformation info, int size, out int returned);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, IntPtr size, out IntPtr read);

    [DllImport("kernel32.dll")]
    static extern bool CloseHandle(IntPtr handle);

    public static string[] ListProcesses()
    {
        var rows = new List<string>();
        IntPtr snapshot = CreateToolhelp32Snapshot(0x2, 0);
        if (snapshot == IntPtr.Zero || snapshot == new IntPtr(-1)) return rows.ToArray();
        try
        {
            var entry = new ProcessEntry();
            entry.Size = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            bool more = Process32FirstW(snapshot, ref entry);
            while (more)
            {
                rows.Add(entry.ProcessId + "|" + entry.ParentProcessId + "|" + entry.ExeFile);
                more = Process32NextW(snapshot, ref entry);
            }
        }
        finally
        {
            CloseHandle(snapshot);
        }
        return rows.ToArray();
    }

    static byte[] Read(IntPtr process, IntPtr address, int size)
    {
        var buffer = new byte[size];
        IntPtr read;
        if (!ReadProcessMemory(process, address, buffer, new IntPtr(size), out read)) return null;
        return buffer;
    }

    public static string GetEnvironmentVariable(int processId, string name)
    {
        if (IntPtr.Size != 8) return null;
        IntPtr process = OpenProcess(0x0410, false, processId);
        if (process == IntPtr.Zero) return null;
        try
        {
            var info = new ProcessBasicInformation();
            int returned;
            if (NtQueryInformationProcess(process, 0, ref info, Marshal.SizeOf(info), out returned) != 0) return null;
            byte[] peb = Read(process, info.PebBaseAddress, 0x28);
            if (peb == null) return null;
            IntPtr parameters = new IntPtr(BitConverter.ToInt64(peb, 0x20));
            byte[] header = Read(process, parameters, 0x400);
            if (header == null) return null;
            IntPtr environment = new IntPtr(BitConverter.ToInt64(header, 0x80));
            long length = BitConverter.ToInt64(header, 0x3F0);
            if (length <= 0 || length > 1048576) return null;
            byte[] block = Read(process, environment, (int)length);
            if (block == null) return null;
            string prefix = name + "=";
            foreach (string variable in Encoding.Unicode.GetString(block).Split('\0'))
            {
                if (variable.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return variable.Substring(prefix.Length);
            }
            return null;
        }
        finally
        {
            CloseHandle(process);
        }
    }
}
