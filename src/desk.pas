unit desk;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, OleCtrls, MyWebBrowser;

type
  TDeskExternalConnection = record
   OnDocumentComplete : procedure (); cdecl;
   OnRClick : procedure (); cdecl;
   OnMouseDown : procedure (); cdecl;
   GetCompLoc : function () : pchar; cdecl;
   GetCompDesc : function () : pchar; cdecl;
   GetStudentSessionName : function () : pchar; cdecl;
   GetStatusString : function () : pchar; cdecl;
   GetInfoText : function () : pchar; cdecl;
   GetNumSheets : function () : integer; cdecl;
   GetSheetName : function (idx:integer) : pchar; cdecl;
   IsSheetActive : function (idx:integer) : longbool; cdecl;
   SetSheetActive : procedure (idx:integer;active:longbool); cdecl;
   GetSheetBGPic : function (idx:integer) : pchar; cdecl;
   IsPageShaded : function () : longbool; cdecl;
   DoShellExec : procedure (const exe,args:pchar); cdecl;
   GetInputText : function (const title,text:pchar):pchar; cdecl;
   Alert : procedure (const text:pchar); cdecl;
   GetInputTextPos : function (pwdchar:char;x,y,w,h,maxlen:integer;const text:pchar):pchar; cdecl;
   //....
  end;
  PDeskExternalConnection = ^TDeskExternalConnection;

type
  TKNDeskForm = class(TForm)
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Private declarations }
    WebBrowser : TMyWebBrowser;
    last_nav_url: string;
    conn : PDeskExternalConnection;

    procedure CreateWebBrowser();
    procedure DestroyWebBrowser();

    procedure WebBrowserBeforeNavigate2(Sender: TObject;
      const pDisp: IDispatch; var URL, Flags, TargetFrameName, PostData,
      Headers: OleVariant; var Cancel: WordBool);
    procedure WebBrowserNewWindow2(Sender: TObject; var ppDisp: IDispatch;
      var Cancel: WordBool);
    procedure WebBrowserWindowClosing(ASender: TObject; IsChildWindow: WordBool; var Cancel: WordBool);
    procedure WebBrowserDocumentComplete(Sender: TObject;
      const pDisp: IDispatch; var URL: OleVariant);
    procedure OnRClick();
    procedure OnMouseDown();

    function KNGetCompLoc(Params: array of OleVariant): OleVariant;
    function KNGetCompDesc(Params: array of OleVariant): OleVariant;
    function KNGetStudentSessionName(Params: array of OleVariant): OleVariant;
    function KNGetNumSheets(Params: array of OleVariant): OleVariant;
    function KNGetSheetName(Params: array of OleVariant): OleVariant;
    function KNIsSheetActive(Params: array of OleVariant): OleVariant;
    function KNSetSheetActive(Params: array of OleVariant): OleVariant;
    function KNGetSheetBGPic(Params: array of OleVariant): OleVariant;
    function KNGetStatusString(Params: array of OleVariant): OleVariant;
    function KNGetInfoText(Params: array of OleVariant): OleVariant;
    function KNIsPageShaded(Params: array of OleVariant): OleVariant;
    function KNGetResTranslatedUrl(Params: array of OleVariant): OleVariant;
    function KNDoShellExec(Params: array of OleVariant): OleVariant;
    function KNGetInputText(Params: array of OleVariant): OleVariant;
    function KNAlert(Params: array of OleVariant): OleVariant;
    function KNInputWrapper(Params: array of OleVariant): OleVariant;
  public
    { Public declarations }

    constructor MyCreate(p:PDeskExternalConnection);
    destructor Destroy; override;

    procedure DefaultHandler(var Message); override;

    function MyIsVisible:boolean;
    procedure MyShow();
    procedure MyHide();
    procedure MyRepaint();
    procedure MyRefresh();
    procedure MyNavigate(url:string);
    procedure MyOnDisplayChange();
    procedure MyOnEndSession();
    procedure MyBringToBottom();
    procedure MyOnStatusStringChanged();
    procedure MyOnActiveSheetChanged();
    procedure MyOnPageShaded();
  end;



implementation

uses StrUtils, Registry, tools;

{$R *.dfm}


function UrlUnescape(pszURL,pszUnescaped:pchar; pcchUnescaped:PDWORD; dwFlags:DWORD):HRESULT; stdcall; external 'shlwapi.dll' name 'UrlUnescapeA';
function UrlEscape(const pszURL:pchar; pszEscaped:pchar; pcchEscaped:PDWORD; dwFlags:DWORD):HRESULT; stdcall; external 'shlwapi.dll' name 'UrlEscapeA';

const URL_DONT_UNESCAPE_EXTRA_INFO    = $02000000;
const URL_UNESCAPE_INPLACE            = $00100000;
const URL_ESCAPE_SPACES_ONLY          = $04000000;

const WM_XBUTTONDOWN    =              $020B;
const WM_XBUTTONUP      =              $020C;
const WM_XBUTTONDBLCLK  =              $020D;

var
    hook1 : cardinal = 0;
    hook2 : cardinal = 0;
    g_hwnd : HWND = 0;
    msg_rclick : cardinal = WM_NULL;
    msg_mousedown : cardinal = WM_NULL;
    msg_refresh : cardinal = WM_NULL;



function ComputeResUID(const lib_path,res_name:string):cardinal;
var s:string;
    n:cardinal;
    summ:cardinal;
begin
 s:=AnsiLowerCase(lib_path+'/'+res_name);
 summ:=$A27A2396;
 for n:=1 to length(s) do
  inc(summ,cardinal(ord(s[n]))*n*n);
 Result:=summ;
end;

function ExtractResFile(const href,abs_url,local_url:string):string;
var s,lib_path,res_name:string;
    idx:integer;
    p:array[0..1024] of char;
    dwSize:DWORD;
    err,lib,res,g,data_size:cardinal;
    data_buff:pointer;
    f:integer;
begin
 Result:=local_url;

 if (abs_url='') or (local_url='') then
  Exit;

 if (not AnsiStartsText('res://',href)) or (length(href)<length('res://X:\a')) then
  Exit;

 s:=Copy(href,7,length(href)-6);
 if s[1]='/' then
  s:=Copy(s,2,length(s)-1);

 idx:=AnsiPos('/',s);
 if idx<>0 then
  setlength(s,idx-1);

 StrLCopy(p,pchar(s),sizeof(p)-1);
 dwSize:=sizeof(p)-1;
 UrlUnescape(p,nil,@dwSize,URL_DONT_UNESCAPE_EXTRA_INFO or URL_UNESCAPE_INPLACE);
 lib_path:=p;

 err:=SetErrorMode(SEM_FAILCRITICALERRORS);
 lib:=LoadLibraryEx(pchar(lib_path),0,0);
 if lib=0 then
  lib:=LoadLibraryEx(pchar(lib_path),0,LOAD_LIBRARY_AS_DATAFILE);
 SetErrorMode(err);
 if lib<>0 then
  begin
   res_name:=abs_url;
   res:=FindResource(lib,pchar(AnsiUpperCase(res_name)),pchar(23));
   if res<>0 then
    begin
     g:=LoadResource(lib,res);
     if g<>0 then
      begin
       data_buff:=LockResource(g);
       if data_buff<>nil then
        begin
         data_size:=SizeofResource(lib,res);

         p[0]:=#0;
         GetTempPath(sizeof(p),p);
         s:=p;

         if s<>'' then
          begin
           s:=IncludeTrailingPathDelimiter(s)+'kn_themes_res_tmp\';
           CreateDirectory(pchar(s),nil);

           s:=s+Format('%.8x%s',[ComputeResUID(lib_path,res_name),ExtractFileExt(res_name)]);

           f:=FileCreate(s);
           if f<>-1 then
            begin
             FileWrite(f,data_buff^,data_size);
             FileClose(f);
            end;

           if FileExists(s) then
            begin
             dwSize:=sizeof(p)-1;
             p[0]:=#0;
             if UrlEscape(pchar(s),p,@dwSize,URL_ESCAPE_SPACES_ONLY)=S_OK then
              s:=p;

             s:='file://'+s;
             Result:=s;
            end;
          end;
        end;
      end;
    end;
   FreeLibrary(lib);
  end;
end;

function IsHookInterestWindow(w:HWND):boolean;
begin
 if (w<>0) and IsWindow(w) then
  begin
   if (GetWindowLong(w,GWL_STYLE) and WS_CHILD)<>0 then
    Result:=(GetAncestor(w,GA_ROOT)=g_hwnd)
   else
    Result:=(w=g_hwnd);
  end
 else
  Result:=false;
end;

function IsFlashWindow(w:HWND):boolean;
var s:array[0..MAX_PATH] of char;
begin
 if (w<>0) and IsWindow(w) and ((GetWindowLong(w,GWL_STYLE) and WS_CHILD)<>0) then
  begin
   s[0]:=#0;
   GetClassName(w,s,sizeof(s));
   Result:=(string(s)='MacromediaFlashPlayerActiveX');
  end
 else
  Result:=false;
end;

function CBTProc(code: integer; wParam: integer; lParam: integer): integer stdcall;
begin
 if code >= 0 then
  begin
   if {(code=HCBT_ACTIVATE) or} (code=HCBT_SETFOCUS) then
    begin
     if IsHookInterestWindow(wParam) then
      begin
       Result:=1;
       exit;
      end;
    end;
  end;
 Result := CallNextHookEx(hook1, Code, wParam, lParam);
end;

function GMProc(code: integer; wParam: integer; lParam: integer): integer stdcall;
var p:PMSG;
begin
 if code >= 0 then
  begin
   p:=PMSG(lParam);
   if (p^.message=WM_LBUTTONDOWN) or
      (p^.message=WM_LBUTTONUP) or
      (p^.message=WM_LBUTTONDBLCLK) or
      (p^.message=WM_RBUTTONDOWN) or
      (p^.message=WM_RBUTTONUP) or
      (p^.message=WM_RBUTTONDBLCLK) or
      (p^.message=WM_MBUTTONDOWN) or
      (p^.message=WM_MBUTTONUP) or
      (p^.message=WM_MBUTTONDBLCLK) or
      (p^.message=WM_XBUTTONDOWN) or
      (p^.message=WM_XBUTTONUP) or
      (p^.message=WM_XBUTTONDBLCLK) or
      (p^.message=WM_MOUSEWHEEL) or
      (p^.message=WM_MOUSEMOVE) or
      (p^.message=WM_KEYDOWN) or
      (p^.message=WM_KEYUP) or
      (p^.message=WM_SYSKEYDOWN) or
      (p^.message=WM_SYSKEYUP) or
      (p^.message=WM_SYSCHAR) or
      (p^.message=WM_CHAR) then
     begin
      if IsHookInterestWindow(p^.hwnd) then
       begin
        if (p^.message=WM_LBUTTONDOWN) or 
           (p^.message=WM_RBUTTONDOWN) or 
           (p^.message=WM_MBUTTONDOWN) then
          PostMessage(g_hwnd,msg_mousedown,0,0);
        if p^.message=WM_RBUTTONUP then
          PostMessage(g_hwnd,msg_rclick,0,0);
        if (p^.message=WM_KEYDOWN) and (p^.wParam=VK_F5) then
          PostMessage(g_hwnd,msg_refresh,0,0);

        if (p^.message<>WM_LBUTTONDOWN) and
           (p^.message<>WM_LBUTTONUP) and
           (p^.message<>WM_LBUTTONDBLCLK) and
           (p^.message<>WM_MOUSEMOVE) then
         begin
          p^.message:=WM_NULL;
          Result:=0;
          exit;
         end
        else
         begin
          if p^.message=WM_MOUSEMOVE then
           begin
            if (p^.wParam and MK_LBUTTON)<>0 then
             begin
              p^.message:=WM_NULL;
              Result:=0;
              exit;
             end;
           end;
         end;
       end;
     end;
  end;

 Result := CallNextHookEx(hook2, Code, wParam, lParam);
end;

procedure InitHooks(w:HWND);
begin
 if g_hwnd=0 then
  g_hwnd:=w;
 if hook1=0 then
  hook1:=SetWindowsHookEx(WH_CBT,CBTProc,0,GetCurrentThreadId());
 if hook2=0 then
  hook2:=SetWindowsHookEx(WH_GETMESSAGE,GMProc,0,GetCurrentThreadId());
end;

procedure DoneHooks;
begin
 if hook1<>0 then
  UnhookWindowsHookEx(hook1);
 hook1:=0;
 if hook2<>0 then
  UnhookWindowsHookEx(hook2);
 hook2:=0;
 g_hwnd:=0;
end;

procedure TKNDeskForm.DefaultHandler(var Message);
begin
 with TMessage(Message) do
   if msg=msg_rclick then
     OnRClick()
   else
   if msg=msg_mousedown then
     OnMouseDown()
   else
   if msg=msg_refresh then
     MyRefresh()
   else
     inherited;
end;

constructor TKNDeskForm.MyCreate(p:PDeskExternalConnection);
begin
 inherited Create(nil);

 WebBrowser:=nil;
 last_nav_url:='';
 conn:=p;

 SetWindowLong(Handle,GWL_EXSTYLE,WS_EX_TOOLWINDOW {or WS_EX_TOPMOST{or WS_EX_NOACTIVATE});
 SetWindowLong(Handle,GWL_STYLE,integer(WS_POPUP or WS_CLIPCHILDREN or WS_CLIPSIBLINGS));

 InitHooks(Handle);

 Left:=0;
 Top:=0;
 Width:=Screen.Width;
 Height:=Screen.Height;

 //SetWindowPos(Handle,0,0,0,Screen.Width,Screen.Height,SWP_NOACTIVATE or SWP_NOOWNERZORDER);
end;

destructor TKNDeskForm.Destroy;
begin
 DoneHooks;
 conn:=nil;
 DestroyWebBrowser();

 inherited;
end;

procedure TKNDeskForm.FormCloseQuery(Sender: TObject;
  var CanClose: Boolean);
begin
 CanClose:=false;
end;

procedure TKNDeskForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
 Action:=caNone;
end;

procedure TKNDeskForm.OnRClick();
begin
 if conn<>nil then
  if @conn.OnRClick<>nil then
   conn.OnRClick();
end;

procedure TKNDeskForm.OnMouseDown();
begin
 if conn<>nil then
  if @conn.OnMouseDown<>nil then
   conn.OnMouseDown();
end;


procedure TKNDeskForm.CreateWebBrowser();
var reg:TRegistry;
    t:array[0..MAX_PATH] of char;
    exename:string;
begin
 if WebBrowser=nil then
  begin
    // Enable IE8+ engine
    reg:=TRegistry.Create;
    t[0]:=#0;
    Windows.GetModuleFileName(0,t,sizeof(t));
    exename:=ExtractFileName(string(t));
    WriteRegDword(reg,'Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION',exename,9999);
    reg.Free;
    
    WebBrowser:=TMyWebBrowser.Create(nil);

    WebBrowser.TabStop:=false;
    WebBrowser.Align:=alClient;

    WebBrowser.ContextMenuEnabled:=false;
    WebBrowser.Border3DEnabled:=false;
    WebBrowser.ScrollEnabled:=false;
    WebBrowser.TextSelectEnabled:=false;
    WebBrowser.AllowFileDownload:=false;
    WebBrowser.AllowAlerts:=false;
    WebBrowser.DLOptions:=[dlImages, dlVideos, dlSounds, dlNoJava, dlNoActiveXDownload{, dlSilent}];

    WebBrowser.OnBeforeNavigate2 := WebBrowserBeforeNavigate2;
    WebBrowser.OnNewWindow2 := WebBrowserNewWindow2;
    WebBrowser.OnWindowClosing := WebBrowserWindowClosing;
    WebBrowser.OnDocumentComplete := WebBrowserDocumentComplete;

    WebBrowser.Bind('getComputerLoc',KNGetCompLoc);
    WebBrowser.Bind('getComputerDesc',KNGetCompDesc);
    WebBrowser.Bind('getStudentSessionName',KNGetStudentSessionName);
    WebBrowser.Bind('getStatusString',KNGetStatusString);
    WebBrowser.Bind('getInfoText',KNGetInfoText);
    WebBrowser.Bind('getNumSheets',KNGetNumSheets);
    WebBrowser.Bind('getSheetName',KNGetSheetName);
    WebBrowser.Bind('isSheetActive',KNIsSheetActive);
    WebBrowser.Bind('setSheetActive',KNSetSheetActive);
    WebBrowser.Bind('getSheetBGPic',KNGetSheetBGPic);
    WebBrowser.Bind('isPageShaded',KNIsPageShaded);
    WebBrowser.Bind('getResTranslatedUrl',KNGetResTranslatedUrl);
    WebBrowser.Bind('doShellExec',KNDoShellExec);
    WebBrowser.Bind('getInputText',KNGetInputText);
    WebBrowser.Bind('alert',KNAlert);
    WebBrowser.Bind('inputWrapper',KNInputWrapper);
    //.....

    TWinControl(WebBrowser).Parent:=self;
  end;
end;

procedure TKNDeskForm.DestroyWebBrowser();
begin
 if WebBrowser<>nil then
  begin
   try
    if WebBrowser.Busy then
     WebBrowser.Stop;
   except end;
   TWinControl(WebBrowser).Parent:=nil;
   WebBrowser.Free;
   WebBrowser:=nil;
  end;
end;

procedure TKNDeskForm.WebBrowserBeforeNavigate2(Sender: TObject;
  const pDisp: IDispatch; var URL, Flags, TargetFrameName, PostData,
  Headers: OleVariant; var Cancel: WordBool);
begin
 Cancel:=false;

 //todo: check last_nav_url and URL here..

end;

procedure TKNDeskForm.WebBrowserNewWindow2(Sender: TObject;
  var ppDisp: IDispatch; var Cancel: WordBool);
begin
 Cancel:=TRUE;
end;

procedure TKNDeskForm.WebBrowserWindowClosing(ASender: TObject; IsChildWindow: WordBool; var Cancel: WordBool);
begin
 Cancel:=TRUE;
end;

procedure TKNDeskForm.WebBrowserDocumentComplete(Sender: TObject;
  const pDisp: IDispatch; var URL: OleVariant);
begin
 if (WebBrowser<>nil) and (WebBrowser.Application=pDisp) then
  begin
   if (conn<>nil) and (@conn.OnDocumentComplete<>nil) then
    conn.OnDocumentComplete();
  end;
end;

procedure TKNDeskForm.MyRepaint();
begin
 if WebBrowser<>nil then
  begin
   WebBrowser.Repaint;
  end
 else
  begin
   InvalidateRect(Handle,nil,TRUE);
   Windows.UpdateWindow(Handle);
  end;
end;

procedure TKNDeskForm.MyRefresh();
begin
 if WebBrowser<>nil then
  begin
   try
    //parm:OleVariant;
    //parm:=3;//REFRESH_COMPLETELY;
    //WebBrowser.Refresh2(parm);
    WebBrowser.Refresh;
   except end;
  end
 else
  begin
   MyRepaint();
  end;
end;

procedure TKNDeskForm.MyNavigate(url:string);
begin
 if url='' then
  begin
   DestroyWebBrowser();
   MyRepaint();
   if (conn<>nil) and (@conn.OnDocumentComplete<>nil) then
    conn.OnDocumentComplete();
  end
 else
  begin
   CreateWebBrowser();
   if WebBrowser<>nil then
    begin
     try
      WebBrowser.Navigate(url);
      last_nav_url:=url;
     except
      if (conn<>nil) and (@conn.OnDocumentComplete<>nil) then
       conn.OnDocumentComplete();
     end;
     MyRepaint();
    end
   else
    begin
     MyRepaint();
     if (conn<>nil) and (@conn.OnDocumentComplete<>nil) then
      conn.OnDocumentComplete();
    end;
  end;
end;

procedure TKNDeskForm.MyShow();
begin
 if not IsWindowVisible(Handle) then
  begin
   if Visible then
    Visible:=false;
//   SetWindowPos(Handle,HWND_BOTTOM,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_NOSENDCHANGING or SWP_SHOWWINDOW);
//   Visible:=true;
   Show;
//   MyBringToBottom();
   MyRepaint();
  end;
end;

procedure TKNDeskForm.MyHide();
begin
 Visible:=false;
end;

function TKNDeskForm.MyIsVisible:boolean;
begin
 Result:=IsWindowVisible(Handle);
end;

procedure TKNDeskForm.MyOnDisplayChange();
begin
// SetWindowPos(Handle,HWND_BOTTOM,0,0,Screen.Width,Screen.Height,SWP_NOACTIVATE);
// MyRepaint();
end;

procedure TKNDeskForm.MyOnEndSession();
begin
 Visible:=false;
// DoneHooks;
end;

procedure TKNDeskForm.MyBringToBottom();
begin
// SetWindowPos(Handle,HWND_BOTTOM,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE or SWP_NOSENDCHANGING);
end;

function TKNDeskForm.KNGetCompLoc(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.GetCompLoc<>nil) then
   Result:=string(conn.GetCompLoc())
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNGetCompDesc(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.GetCompDesc<>nil) then
   Result:=string(conn.GetCompDesc())
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNGetStudentSessionName(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.GetStudentSessionName<>nil) then
   Result:=string(conn.GetStudentSessionName())
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNGetNumSheets(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.GetNumSheets<>nil) then
   Result:=conn.GetNumSheets()
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNGetSheetName(Params: array of OleVariant): OleVariant;
var idx:integer;
begin
 Result:=unassigned;

 if length(Params)=1 then
  begin
   try
    idx:=integer(Params[0]);
    if (conn<>nil) and (@conn.GetSheetName<>nil) then
      Result:=string(conn.GetSheetName(idx));
   except
   end;
  end;
end;

function TKNDeskForm.KNIsSheetActive(Params: array of OleVariant): OleVariant;
var idx:integer;
begin
 Result:=unassigned;

 if length(Params)=1 then
  begin
   try
    idx:=integer(Params[0]);
    if (conn<>nil) and (@conn.IsSheetActive<>nil) then
      Result:=conn.IsSheetActive(idx);
   except
   end;
  end;
end;

function TKNDeskForm.KNSetSheetActive(Params: array of OleVariant): OleVariant;
var idx:integer;
    state:boolean;
begin
 Result:=unassigned;

 if length(Params)=2 then
  begin
   try
    idx:=integer(Params[1]);
    try
     state:=boolean(Params[0]);

     if (conn<>nil) and (@conn.SetSheetActive<>nil) then
       conn.SetSheetActive(idx,state);
    except
    end;
   except
   end;
  end;
end;

function TKNDeskForm.KNGetSheetBGPic(Params: array of OleVariant): OleVariant;
var idx:integer;
begin
 Result:=unassigned;

 if length(Params)=1 then
  begin
   try
    idx:=integer(Params[0]);
    if (conn<>nil) and (@conn.GetSheetBGPic<>nil) then
      Result:=string(conn.GetSheetBGPic(idx));
   except
   end;
  end;
end;

function TKNDeskForm.KNGetStatusString(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.GetStatusString<>nil) then
   Result:=string(conn.GetStatusString())
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNGetInfoText(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.GetInfoText<>nil) then
   Result:=string(conn.GetInfoText())
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNIsPageShaded(Params: array of OleVariant): OleVariant;
begin
 if (conn<>nil) and (@conn.IsPageShaded<>nil) then
   Result:=conn.IsPageShaded()
 else
   Result:=unassigned;
end;

function TKNDeskForm.KNGetResTranslatedUrl(Params: array of OleVariant): OleVariant;
var s_href,s_res,s_url : string;
begin
 Result:=unassigned;

 if length(Params)=3 then
  begin
   try
    s_href:=string(Params[2]);
    s_res:=string(Params[1]);
    s_url:=string(Params[0]);

    Result:=ExtractResFile(s_href,s_res,s_url);
   except
   end;
  end;
end;

function TKNDeskForm.KNDoShellExec(Params: array of OleVariant): OleVariant;
var exe,args:string;
begin
 Result:=unassigned;

 exe:='';
 args:='';
 
 if length(Params)=2 then
  begin
   try
    exe:=string(Params[1]);
    args:=string(Params[0]);
   except
   end;
  end
 else
 if length(Params)=1 then
  begin
   try
    exe:=string(Params[0]);
   except
   end;
  end;

 if exe<>'' then
  begin
   if (conn<>nil) and (@conn.DoShellExec<>nil) then
     conn.DoShellExec(pchar(exe),pchar(args));
  end;
end;

function TKNDeskForm.KNGetInputText(Params: array of OleVariant): OleVariant;
var title,text:string;
begin
 Result:=unassigned;

 if length(Params)=2 then
  begin
   title:='';
   text:='';

   try
    title:=string(Params[1]);
    text:=string(Params[0]);
   except
   end;

   if (conn<>nil) and (@conn.GetInputText<>nil) then
     Result:=widestring(string(conn.GetInputText(pchar(title),pchar(text))));
  end;
end;


function TKNDeskForm.KNAlert(Params: array of OleVariant): OleVariant;
var text:string;
begin
 Result:=unassigned;

 if length(Params)=1 then
  begin
   text:='';

   try
    text:=string(Params[0]);
   except
   end;

   if (conn<>nil) and (@conn.Alert<>nil) then
     conn.Alert(pchar(text));
  end;
end;


function GetElAbsX(el:OleVariant):integer;
var t:OleVariant;
begin
 Result:=0;

 try
  t:=el;
  while true do
   begin
    Result := Result + integer(t.offsetLeft);
    t := t.offsetParent;
   end;
 except
 end;

 try
  t:=el;
  while true do
   begin
    t := t.parentElement;
    Result := Result - integer(t.scrollLeft);
   end;
 except
 end;
end;


function GetElAbsY(el:OleVariant):integer;
var t:OleVariant;
begin
 Result:=0;

 try
  t:=el;
  while true do
   begin
    Result := Result + integer(t.offsetTop);
    t := t.offsetParent;
   end;
 except
 end;

 try
  t:=el;
  while true do
   begin
    t := t.parentElement;
    Result := Result - integer(t.scrollTop);
   end;
 except
 end;
end;


function TKNDeskForm.KNInputWrapper(Params: array of OleVariant): OleVariant;
var x,y,w,h,maxlen:integer;
    pwdchar:char;
    intext,objtype:string;
    obj:OleVariant;
    is_text,is_pwd:boolean;
begin
 Result:=unassigned;

 if length(Params)=1 then
  begin
   Result:=true;
   
   obj:=Params[0];

   try objtype:=obj.type; except objtype:=''; end;

   is_text:=(AnsiCompareText(objtype,'text')=0) or (AnsiCompareText(objtype,'textarea')=0);
   is_pwd:=AnsiCompareText(objtype,'password')=0;

   if is_text or is_pwd then
    begin
     if is_text then
      pwdchar:=#0
     else
      pwdchar:='*';

     x:=GetElAbsX(obj);
     y:=GetElAbsY(obj);

     try w:=obj.offsetWidth; except w:=100; end;
     try h:=obj.offsetHeight; except h:=20; end;
     try maxlen:=obj.maxLength; except maxlen:=$7FFFFFFF; end;
     try intext:=obj.value; except intext:=''; end;

     if (conn<>nil) and (@conn.GetInputTextPos<>nil) then
      begin
       try
        obj.value:=widestring(string(conn.GetInputTextPos(pwdchar,x,y,w,h,maxlen,pchar(intext))));
       except
       end;
      end;
    end;
  end;
end;


procedure TKNDeskForm.MyOnStatusStringChanged();
begin
 if WebBrowser<>nil then
  begin
   try
    WebBrowser.InvokeScript('OnStatusStringChanged',[]);
   except
   end;
  end;
end;

procedure TKNDeskForm.MyOnActiveSheetChanged();
begin
 if WebBrowser<>nil then
  begin
   try
    WebBrowser.InvokeScript('OnActiveSheetChanged',[]);
   except
   end;
  end;
end;

procedure TKNDeskForm.MyOnPageShaded();
begin
 if WebBrowser<>nil then
  begin
   try
    WebBrowser.InvokeScript('OnPageShaded',[]);
   except
   end;
  end;
end;

begin
 msg_rclick:=RegisterWindowMessage('KNDeskForm.RClick');
 msg_mousedown:=RegisterWindowMessage('KNDeskForm.MouseDown');
 msg_refresh:=RegisterWindowMessage('KNDeskForm.F5');
end.

