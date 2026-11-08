# Grants "Log on as a batch job" (SeBatchLogonRight) to an account. Run as administrator.
# Windows 10 Home has no Local Security Policy window and `secedit` failed in the spike,
# so this calls LsaAddAccountRights directly.
#   .\grant-batch-logon.ps1 -Account trainer
#   .\grant-batch-logon.ps1 -Account S-1-5-21-...-1011
# Prints 0 on success.
param(
    [Parameter(Mandatory = $true)][string]$Account
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public static class LsaRights
{
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING
    {
        public ushort Length;
        public ushort MaximumLength;
        [MarshalAs(UnmanagedType.LPWStr)] public string Buffer;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES
    {
        public int Length;
        public IntPtr RootDirectory;
        public IntPtr ObjectName;
        public uint Attributes;
        public IntPtr SecurityDescriptor;
        public IntPtr SecurityQualityOfService;
    }

    [DllImport("advapi32.dll")]
    static extern uint LsaOpenPolicy(ref LSA_UNICODE_STRING systemName,
        ref LSA_OBJECT_ATTRIBUTES attributes, uint access, out IntPtr policy);

    [DllImport("advapi32.dll")]
    static extern uint LsaAddAccountRights(IntPtr policy, byte[] sid,
        LSA_UNICODE_STRING[] rights, uint count);

    [DllImport("advapi32.dll")]
    static extern uint LsaClose(IntPtr policy);

    [DllImport("advapi32.dll")]
    static extern uint LsaNtStatusToWinError(uint status);

    public static uint Grant(string account, string right)
    {
        SecurityIdentifier sid;
        if (account.StartsWith("S-1-"))
            sid = new SecurityIdentifier(account);
        else
            sid = (SecurityIdentifier)new NTAccount(account).Translate(typeof(SecurityIdentifier));
        byte[] sidBytes = new byte[sid.BinaryLength];
        sid.GetBinaryForm(sidBytes, 0);

        LSA_UNICODE_STRING system = new LSA_UNICODE_STRING();
        LSA_OBJECT_ATTRIBUTES attrs = new LSA_OBJECT_ATTRIBUTES();
        attrs.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
        IntPtr policy;
        uint status = LsaOpenPolicy(ref system, ref attrs, 0x810, out policy);
        if (status != 0) return LsaNtStatusToWinError(status);
        try
        {
            LSA_UNICODE_STRING[] rights = new LSA_UNICODE_STRING[1];
            rights[0].Buffer = right;
            rights[0].Length = (ushort)(right.Length * 2);
            rights[0].MaximumLength = (ushort)(right.Length * 2 + 2);
            return LsaNtStatusToWinError(LsaAddAccountRights(policy, sidBytes, rights, 1));
        }
        finally
        {
            LsaClose(policy);
        }
    }
}
'@

[LsaRights]::Grant($Account, 'SeBatchLogonRight')
