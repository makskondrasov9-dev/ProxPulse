import Foundation
import ProxPulseCore

private final class SSHProcessBox: @unchecked Sendable {
    let process = Process()
    func stop() { if process.isRunning { process.terminate() } }
}

/// Uses existing SSH authentication and host trust. The script only reads runtime links,
/// counters and public endpoints; no credentials or configuration are returned or changed.
enum TunnelProbe {
    static func discover(host: String, user: String) async throws -> RuntimeNetworkSnapshot {
        _ = try SSHCommand.make(host: host, user: user)
        return try await Task.detached(priority: .utility) {
            let box = SSHProcessBox()
            let process = box.process
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=4", "-o", "ConnectionAttempts=1", "-o", "ServerAliveInterval=3", "-o", "ServerAliveCountMax=1", "-l", user, "--", host, "python3 -"]
            let input = Pipe(), output = Pipe()
            process.standardInput = input; process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem { box.stop() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 18, execute: timeout)
            defer { timeout.cancel() }
            try input.fileHandleForWriting.write(contentsOf: Data(script.utf8))
            try input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw ProvisionError.invalid("SSH-пробник недоступен. Нужны SSH-ключ, доверенный known_hosts и Python 3 на ноде.")
            }
            return try JSONDecoder().decode(RuntimeNetworkSnapshot.self, from: data)
        }.value
    }

    static let script = #"""
import time,json,subprocess,re,pathlib,ipaddress
root=pathlib.Path('/sys/class/net')
errors={}
try:
 links=json.loads(subprocess.run(['ip','-j','link','show'],capture_output=True,text=True,timeout=3,check=True).stdout)
except (OSError,ValueError,subprocess.SubprocessError):
 links=[]
 for path in root.iterdir():
  try: links.append({'ifname':path.name,'flags':['UP'] if int((path/'flags').read_text(),16)&1 else []})
  except (OSError,ValueError): pass
interfaces=[]
for link in links:
 name=link.get('ifname','').split('@')[0]
 if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}',name): continue
 tunnel=bool(re.match(r'^(awg|wg|tun)',name))
 bridge=(root/name/'bridge').exists() and not name.startswith(('fwbr','fwln','fwpr'))
 if tunnel or bridge:
  interfaces.append({'iface':name,'type':'tunnel' if tunnel else 'bridge','active':1 if 'UP' in link.get('flags',[]) else 0})
def counters(name):
 path=root/name/'statistics'
 return int((path/'rx_bytes').read_text()),int((path/'tx_bytes').read_text())
first={}
for interface in interfaces:
 if interface['active']:
  try: first[interface['iface']]=counters(interface['iface'])
  except (OSError,ValueError): errors[interface['iface']]='Counters unavailable'
start=time.monotonic()
if first: time.sleep(1.0)
elapsed=max(0.001,time.monotonic()-start)
measurements={}
for name,before in first.items():
 try:
  after=counters(name)
  measurements[name]={'receiveBps':max(0,after[0]-before[0])/elapsed,'transmitBps':max(0,after[1]-before[1])/elapsed,'peer':None,'pingMS':None}
 except (OSError,ValueError): errors[name]='Counters unavailable'
for interface in interfaces:
 name=interface['iface']
 if interface['type']!='tunnel' or name not in measurements: continue
 peer=None
 for tool in (['awg','wg'] if name.startswith('awg') else ['wg']):
  try:
   result=subprocess.run([tool,'show',name,'endpoints'],capture_output=True,text=True,timeout=2)
   endpoints=[line.split()[-1] for line in result.stdout.splitlines() if line.split()]
   endpoint=next((x for x in endpoints if x!='(none)'),None)
   if endpoint: peer=endpoint.rsplit(':',1)[0].strip('[]')
  except (OSError,subprocess.TimeoutExpired): pass
  if peer: break
 if not peer:
  try:
   routes=json.loads(subprocess.run(['ip','-j','route','show','dev',name],capture_output=True,text=True,timeout=2).stdout)
   peer=next((x.get('gateway') for x in routes if x.get('gateway')),None)
  except (OSError,ValueError,subprocess.TimeoutExpired): pass
 measurements[name]['peer']=peer
 if peer:
  try:
   ipaddress.ip_address(peer)
   result=subprocess.run(['ping','-n','-c','2','-W','1',peer],capture_output=True,text=True,timeout=3)
   times=[float(x) for x in re.findall(r'time[=<]([0-9.]+)',result.stdout)]
   if times: measurements[name]['pingMS']=sum(times)/len(times)
  except (ValueError,OSError,subprocess.TimeoutExpired): pass
print(json.dumps({'interfaces':interfaces,'measurements':measurements,'errors':errors}))
"""#
}
