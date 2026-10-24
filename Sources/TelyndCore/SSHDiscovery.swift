import Foundation

public enum SSHDiscovery {
    /// Run by the user on Linux. Reads public connection details only.
    public static let command = """
    telynd_user=$(whoami)
    printf 'Linux username (first field): %s\\n' "$telynd_user"
    telynd_vpn=''
    if command -v tailscale >/dev/null 2>&1; then
      telynd_vpn=$(tailscale ip -4 2>/dev/null) || telynd_vpn=''
    fi
    if [ -n "$telynd_vpn" ]; then
      printf '\\nSSH via Tailscale (use if both devices share this Tailscale network):\\n'
      printf 'ssh %s@%s\\n' "$telynd_user" "$telynd_vpn"
    fi
    printf '\\nOther IPv4 SSH addresses (choose a network reachable from your Mac):\\n'
    for telynd_host in $(hostname -I); do
      case "$telynd_host" in *:*) continue ;; esac
      [ "$telynd_host" = "$telynd_vpn" ] || printf 'ssh %s@%s\\n' "$telynd_user" "$telynd_host"
    done
    printf '\\nSSH identity fingerprints (compare when SSH asks whether to trust this computer):\\n'
    for telynd_key in /etc/ssh/ssh_host_*_key.pub; do
      [ ! -f "$telynd_key" ] || ssh-keygen -lf "$telynd_key"
    done
    """
}
