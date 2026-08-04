using System.Net.Http.Json;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text;

namespace CamoNASAdmin.Windows;

public sealed class ServerPairing
{
    internal const string CredentialPrefix = "CamoNASAdmin:";

    public async Task PairAsync(string serverUrl, string deviceName, string pin)
    {
        if (!Uri.TryCreate(serverUrl, UriKind.Absolute, out var baseUri) || baseUri.Scheme != Uri.UriSchemeHttps) throw new InvalidOperationException("Use an HTTPS Camo NAS server URL.");
        if (string.IsNullOrWhiteSpace(deviceName) || string.IsNullOrWhiteSpace(pin)) throw new InvalidOperationException("Enter a device name and pairing PIN.");
        using var client = new HttpClient { BaseAddress = baseUri };
        using var response = await client.PostAsJsonAsync("/pairing/pair", new { device_name = deviceName.Trim(), pin = pin.Trim() });
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadFromJsonAsync<PairingResponse>() ?? throw new InvalidOperationException("The server returned an invalid pairing response.");
        CredentialStore.Save(baseUri.GetLeftPart(UriPartial.Authority), result.Token);
    }

    public async Task<string> HealthAsync(string serverUrl)
    {
        if (!Uri.TryCreate(serverUrl, UriKind.Absolute, out var baseUri)) throw new InvalidOperationException("Enter a valid server URL.");
        var token = CredentialStore.Read(baseUri.GetLeftPart(UriPartial.Authority)) ?? throw new InvalidOperationException("Pair this Windows client with the server first.");
        using var client = new HttpClient { BaseAddress = baseUri };
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        using var response = await client.GetAsync("/health");
        response.EnsureSuccessStatusCode();
        return "Connected to Camo NAS server.";
    }

    public async Task<List<VmSummary>> VmsAsync(string serverUrl)
    {
        if (!Uri.TryCreate(serverUrl, UriKind.Absolute, out var baseUri)) throw new InvalidOperationException("Enter a valid server URL.");
        var token = CredentialStore.Read(baseUri.GetLeftPart(UriPartial.Authority)) ?? throw new InvalidOperationException("Pair this Windows client with the server first.");
        using var client = new HttpClient { BaseAddress = baseUri };
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        return await client.GetFromJsonAsync<List<VmSummary>>("/vms") ?? [];
    }

    public async Task VmActionAsync(string serverUrl, int vmid, string action)
    {
        if (!Uri.TryCreate(serverUrl, UriKind.Absolute, out var baseUri)) throw new InvalidOperationException("Enter a valid server URL.");
        var token = CredentialStore.Read(baseUri.GetLeftPart(UriPartial.Authority)) ?? throw new InvalidOperationException("Pair this Windows client with the server first.");
        using var client = new HttpClient { BaseAddress = baseUri };
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        using var response = await client.PostAsync($"/vms/{vmid}/{action}", null);
        response.EnsureSuccessStatusCode();
    }

    public async Task DeleteVmAsync(string serverUrl, int vmid)
    {
        if (!Uri.TryCreate(serverUrl, UriKind.Absolute, out var baseUri)) throw new InvalidOperationException("Enter a valid server URL.");
        var token = CredentialStore.Read(baseUri.GetLeftPart(UriPartial.Authority)) ?? throw new InvalidOperationException("Pair this Windows client with the server first.");
        using var client = new HttpClient { BaseAddress = baseUri };
        client.DefaultRequestHeaders.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        using var response = await client.DeleteAsync($"/vms/{vmid}");
        response.EnsureSuccessStatusCode();
    }

    private sealed record PairingResponse(string DeviceName, string Token);
}

public sealed record VmSummary(int Vmid, string Name, string Status, int? CpuVcpus, int? MemoryMb)
{
    public string DisplayName => $"{Vmid}  {Name}  ({Status})";
}

internal static class CredentialStore
{
    private const uint CredentialTypeGeneric = 1;
    private const uint CredentialPersistLocalMachine = 2;

    public static void Save(string serverUrl, string token)
    {
        var target = ServerPairing.CredentialPrefix + serverUrl;
        var targetPtr = Marshal.StringToCoTaskMemUni(target);
        var userPtr = Marshal.StringToCoTaskMemUni("Camo NAS device token");
        var blob = Encoding.Unicode.GetBytes(token);
        var blobPtr = Marshal.AllocCoTaskMem(blob.Length);
        try
        {
            Marshal.Copy(blob, 0, blobPtr, blob.Length);
            var credential = new NativeCredential { Type = CredentialTypeGeneric, TargetName = targetPtr, UserName = userPtr, CredentialBlob = blobPtr, CredentialBlobSize = (uint)blob.Length, Persist = CredentialPersistLocalMachine };
            if (!CredWrite(ref credential, 0)) throw new InvalidOperationException($"Windows Credential Manager failed: {Marshal.GetLastWin32Error()}.");
        }
        finally { Marshal.FreeCoTaskMem(targetPtr); Marshal.FreeCoTaskMem(userPtr); Marshal.FreeCoTaskMem(blobPtr); }
    }

    public static string? Read(string serverUrl)
    {
        if (!CredRead(ServerPairing.CredentialPrefix + serverUrl, CredentialTypeGeneric, 0, out var pointer)) return null;
        try { var credential = Marshal.PtrToStructure<NativeCredential>(pointer); return credential.CredentialBlobSize == 0 ? null : Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2); }
        finally { CredFree(pointer); }
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NativeCredential
    {
        public uint Flags, Type;
        public IntPtr TargetName, Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes, TargetAlias, UserName;
    }

    [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite([In] ref NativeCredential userCredential, uint flags);

    [DllImport("Advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("Advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);
}
