// Native SCM adapter. No process execution, remote listener or password storage.
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;

namespace Telynd {
    public sealed class FailureAction {
        public int Type;
        public uint Delay;
    }
    public sealed class FailurePolicy {
        public uint Reset;
        public string Reboot;
        public string Command;
        public FailureAction[] Actions;
    }
    public static class ServicePolicy {
        [StructLayout(LayoutKind.Sequential)] struct NativeAction { public int Type; public uint Delay; }
        [StructLayout(LayoutKind.Sequential)] struct NativePolicy {
            public uint Reset; public IntPtr Reboot; public IntPtr Command; public uint Count; public IntPtr Actions;
        }
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenSCManager(string machine, string database, uint access);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenService(IntPtr manager, string service, uint access);
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool CloseServiceHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError=true)] static extern bool QueryServiceObjectSecurity(IntPtr service, uint information, byte[] buffer, uint size, out uint needed);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryServiceConfig2(IntPtr service, uint level, IntPtr buffer, uint size, out uint needed);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool ChangeServiceConfig2(IntPtr service, uint level, ref NativePolicy policy);
        static IntPtr Open(string name, uint access) {
            var manager = OpenSCManager(null, null, 1);
            if (manager == IntPtr.Zero) throw new Win32Exception();
            try {
                var service = OpenService(manager, name, access);
                if (service == IntPtr.Zero) throw new Win32Exception();
                return service;
            } finally { CloseServiceHandle(manager); }
        }
        public static FailurePolicy Read(string name) {
            var service = Open(name, 1); IntPtr buffer = IntPtr.Zero;
            try {
                uint needed;
                if (QueryServiceConfig2(service, 2, IntPtr.Zero, 0, out needed) || Marshal.GetLastWin32Error() != 122 || needed > 65536) throw new InvalidOperationException("Invalid SCM response");
                buffer = Marshal.AllocHGlobal((int)needed);
                if (!QueryServiceConfig2(service, 2, buffer, needed, out needed)) throw new Win32Exception();
                var p = (NativePolicy)Marshal.PtrToStructure(buffer, typeof(NativePolicy));
                if (p.Count > 64) throw new InvalidOperationException("Too many failure actions");
                var result = new FailurePolicy { Reset=p.Reset, Reboot=Marshal.PtrToStringUni(p.Reboot), Command=Marshal.PtrToStringUni(p.Command), Actions=new FailureAction[p.Count] };
                for (int i=0; i<p.Count; i++) {
                    var action = (NativeAction)Marshal.PtrToStructure(IntPtr.Add(p.Actions, i*Marshal.SizeOf(typeof(NativeAction))), typeof(NativeAction));
                    result.Actions[i] = new FailureAction { Type=action.Type, Delay=action.Delay };
                }
                return result;
            } finally { if (buffer != IntPtr.Zero) Marshal.FreeHGlobal(buffer); CloseServiceHandle(service); }
        }
        public static string Security(string name) {
            var service=Open(name,0x20000);
            try {
                uint needed;
                if(QueryServiceObjectSecurity(service,5,null,0,out needed) || Marshal.GetLastWin32Error()!=122 || needed>65536) throw new InvalidOperationException("Invalid service security response");
                var buffer=new byte[needed];
                if(!QueryServiceObjectSecurity(service,5,buffer,needed,out needed)) throw new Win32Exception();
                return new RawSecurityDescriptor(buffer,0).GetSddlForm(AccessControlSections.Owner | AccessControlSections.Access);
            } finally { CloseServiceHandle(service); }
        }
        public static void Write(string name, FailurePolicy policy) {
            if (policy.Actions == null || policy.Actions.Length > 64) throw new ArgumentException("Invalid failure actions");
            // SERVICE_CHANGE_CONFIG plus SERVICE_START for SC_ACTION_RESTART.
            var service = Open(name, 0x12); var p = new NativePolicy();
            try {
                p.Reset=policy.Reset; p.Count=(uint)policy.Actions.Length;
                p.Reboot=policy.Reboot == null ? IntPtr.Zero : Marshal.StringToHGlobalUni(policy.Reboot);
                p.Command=policy.Command == null ? IntPtr.Zero : Marshal.StringToHGlobalUni(policy.Command);
                // Non-null pointer with zero Count explicitly restores an empty policy.
                p.Actions=Marshal.AllocHGlobal(Math.Max(1, policy.Actions.Length)*Marshal.SizeOf(typeof(NativeAction)));
                for (int i=0; i<policy.Actions.Length; i++) {
                    var a=policy.Actions[i];
                    if (a.Type<0 || a.Type>3) throw new ArgumentException("Invalid action type");
                    Marshal.StructureToPtr(new NativeAction { Type=a.Type, Delay=a.Delay }, IntPtr.Add(p.Actions,i*Marshal.SizeOf(typeof(NativeAction))),false);
                }
                if (!ChangeServiceConfig2(service, 2, ref p)) throw new Win32Exception();
            } finally {
                if(p.Reboot!=IntPtr.Zero) Marshal.FreeHGlobal(p.Reboot);
                if(p.Command!=IntPtr.Zero) Marshal.FreeHGlobal(p.Command);
                if(p.Actions!=IntPtr.Zero) Marshal.FreeHGlobal(p.Actions);
                CloseServiceHandle(service);
            }
        }
    }
}
