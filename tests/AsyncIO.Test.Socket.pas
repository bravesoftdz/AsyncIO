unit AsyncIO.Test.Socket;

interface

procedure RunSocketTest;

implementation

uses
  System.SysUtils, System.DateUtils, AsyncIO, AsyncIO.ErrorCodes, AsyncIO.Net.IP,
  System.Math;

procedure TestAddress;
var
  addr4: IPv4Address;
  addr6: IPv6Address;

  addr: IPAddress;
begin
  addr4 := IPv4Address.Loopback;
  addr := addr4;
  WriteLn('IPv4 loopback: ' + addr);

  addr6 := IPv6Address.Loopback;
  addr := addr6;
  WriteLn('IPv6 loopback: ' + addr);

  addr := IPAddress('192.168.42.2');
  WriteLn('IP address: ' + addr);
  WriteLn('   is IPv4: ' + BoolToStr(addr.IsIPv4, True));
  WriteLn('   is IPv6: ' + BoolToStr(addr.IsIPv6, True));

  addr := IPAddress('abcd::1%42');
  WriteLn('IP address: ' + addr);
  WriteLn('   is IPv4: ' + BoolToStr(addr.IsIPv4, True));
  WriteLn('   is IPv6: ' + BoolToStr(addr.IsIPv6, True));
  WriteLn(' has scope: ' + IntToStr(addr.AsIPv6.ScopeID));

  WriteLn;
end;

procedure TestEndpoint;
var
  endp: IPEndpoint;
begin
  endp := Endpoint(IPAddressFamily.v6, 1234);
  WriteLn('IPv6 listening endpoint: ' + endp);

  endp := Endpoint(IPAddress('192.168.42.1'), 9876);
  WriteLn('IPv4 connection endpoint: ' + endp);

  endp := Endpoint(IPAddress('1234:abcd::1'), 0);
  WriteLn('IPv6 connection endpoint: ' + endp);

  WriteLn;
end;

procedure TestResolve;
var
  qry: IPResolver.Query;
  res: IPResolver.Results;
  ip: IPResolver.Entry;
begin
  qry := Query(IPProtocol.TCPProtocol.v6, 'google.com', '80', [ResolveAllMatching]);
  res := IPResolver.Resolve(qry);

  WriteLn('Resolved ' + qry.HostName + ':' + qry.ServiceName + ' as');
  for ip in res do
  begin
    WriteLn('  ' + ip.Endpoint.Address);
  end;
end;

type
  EchoClient = class
  private
    FRequest: string;
    FRequestData: TBytes;
    FResponseData: TBytes;
    FSocket: IPStreamSocket;
    FStream: AsyncSocketStream;

    procedure ConnectHandler(const ErrorCode: IOErrorCode);
    procedure ReadHandler(const ErrorCode: IOErrorCode; const BytesTransferred: UInt64);
    procedure WriteHandler(const ErrorCode: IOErrorCode; const BytesTransferred: UInt64);
  public
    constructor Create(const Service: IOService;
      const ServerEndpoint: IPEndpoint;
      const Request: string);
  end;

procedure TestEcho;
var
  qry: IPResolver.Query;
  res: IPResolver.Results;
  ip: IPResolver.Entry;
  ios: IOService;
  client: EchoClient;
  r: Int64;
begin
  qry := Query(IPProtocol.TCPProtocol.v6, 'localhost', '7', [ResolveAllMatching]);
  res := IPResolver.Resolve(qry);

  for ip in res do
    // TODO - fix this crap, need way to get first result
    break;

  ios := nil;
  client := nil;
  try
    ios := NewIOService;

    WriteLn('Connecting to ' + ip.Endpoint);

    client := EchoClient.Create(ios, ip.Endpoint, 'Hello Internet!');

    r := ios.Run;

    WriteLn;
    WriteLn(Format('%d handlers executed', [r]));
  finally
    client.Free;
  end;
end;

procedure RunSocketTest;
begin
//  TestAddress;
//  TestEndpoint;
//  TestResolve;

  TestEcho;
end;

{ EchoClient }

procedure EchoClient.ConnectHandler(const ErrorCode: IOErrorCode);
begin
  if (not ErrorCode) then
    RaiseLastOSError(ErrorCode.Value);

  WriteLn('Connected');
  WriteLn('Local endpoint: ' + FSocket.LocalEndpoint);
  WriteLn('Remote endpoint: ' + FSocket.RemoteEndpoint);
  WriteLn('Sending echo request');

  FRequestData := TEncoding.Unicode.GetBytes(FRequest);

  // we'll use a socket stream for the actual read/write operations
  FStream := NewAsyncSocketStream(FSocket);

  AsyncWrite(FStream, FRequestData, TransferAll(), WriteHandler);
end;

constructor EchoClient.Create(
  const Service: IOService;
  const ServerEndpoint: IPEndpoint;
  const Request: string);
begin
  inherited Create;

  FRequest := Request;
  FSocket := TCPSocket(Service);

  FSocket.AsyncConnect(ServerEndpoint, ConnectHandler);
end;

procedure EchoClient.ReadHandler(const ErrorCode: IOErrorCode;
  const BytesTransferred: UInt64);
var
  s: string;
  responseMatches: boolean;
begin
  if (not ErrorCode) then
    RaiseLastOSError(ErrorCode.Value);

  s := TEncoding.Unicode.GetString(FResponseData, 0, BytesTransferred);

  WriteLn('Echo reply: "' + s + '"');

  // compare request and reply
  responseMatches := (Length(FRequestData) = Length(FResponseData)) and
    CompareMem(@FRequestData[0], @FResponseData[0], Length(FRequestData));

  if (responseMatches) then
    WriteLn('Response matches, yay')
  else
    WriteLn('RESPONSE DOES NOT MATCH');

  FSocket.Close();

  // and we're done...
  FStream.Socket.Service.Stop;
end;

procedure EchoClient.WriteHandler(const ErrorCode: IOErrorCode;
  const BytesTransferred: UInt64);
begin
  if (not ErrorCode) then
    RaiseLastOSError(ErrorCode.Value);

  // half close
  FSocket.Shutdown(SocketShutdownWrite);

  // zero our response buffer so we know we got the right stuff back
  FResponseData := nil;
  SetLength(FResponseData, Length(FRequestData));

  AsyncRead(FStream, FResponseData, TransferAtLeast(Length(FResponseData)), ReadHandler);
end;

end.
