//+------------------------------------------------------------------+
//| SiriusSync.mq5 - SIRIUS TR JOURNAL sync (MT5 -> Telegram)        |
//| Шлёт: баланс/эквити, открытые позиции, лимитки, всю историю.     |
//+------------------------------------------------------------------+
#property copyright "SIRIUS"
#property version   "1.00"

input string FirebaseURL     = "https://siriusjurnal-default-rtdb.firebaseio.com";   // Firebase Database URL (рекомендуется), напр. https://xxxx-default-rtdb.firebaseio.com
input string SyncKey         = "";   // Ключ синхронизации (тот же, что в приложении)
input string BotToken        = "";   // (необязательно) Токен бота-ОТПРАВИТЕЛЯ: для Telegram-режима и push
input string ChatID          = "";   // (Telegram-режим) ID канала, напр. -1001234567890
input int    LocalUTCOffset  = 5;    // Ваш часовой пояс (Ташкент = 5)
input int    SnapshotSec     = 20;   // Период отправки баланса/позиций при открытых сделках (сек)
input bool   SendHistory     = true; // Отправить всю историю сделок при запуске
input bool   ResendHistory   = false;// Принудительно отправить историю заново
input string NotifyChatID    = "";   // (необязательно) чат для push-уведомлений о закрытии сделки

string   g_q[];
ulong    g_closeQ[];
ulong    g_nextSend=0;
datetime g_lastSnap=0, g_lastOrdsTime=0;
string   g_lastOrds="";
bool     g_dirty=true, g_histPending=false;
long     g_login=0;

//--- helpers ----------------------------------------------------------
string UrlEnc(const string s)
{
   string r=""; char c[];
   int n=StringToCharArray(s,c,0,WHOLE_ARRAY,CP_UTF8)-1;
   for(int i=0;i<n;i++)
   {
      uchar ch=(uchar)c[i];
      if((ch>='0'&&ch<='9')||(ch>='A'&&ch<='Z')||(ch>='a'&&ch<='z')||ch=='-'||ch=='_'||ch=='.'||ch=='~')
         r+=CharToString(ch);
      else
         r+=StringFormat("%%%02X",ch);
   }
   return r;
}
datetime Loc(datetime t){ return t+(TimeGMT()-TimeCurrent())+LocalUTCOffset*3600; }
string D(datetime t){ string s=TimeToString(Loc(t),TIME_DATE); StringReplace(s,".","-"); return s; }
string H(datetime t){ return TimeToString(Loc(t),TIME_MINUTES); }
string N2(double v){ return DoubleToString(v,2); }
string PR(string sym,double v){ return DoubleToString(v,(int)SymbolInfoInteger(sym,SYMBOL_DIGITS)); }
void Push(string s){ int n=ArraySize(g_q); ArrayResize(g_q,n+1); g_q[n]=s; }

double RiskOf(string sym,double open,double sl,double vol)
{
   if(sl<=0) return 0;
   SymbolSelect(sym,true);
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(ts<=0||tv<=0) return 0;
   return MathAbs(open-sl)/ts*tv*vol;
}
double InitSL(ulong pid,double curSL,bool store)
{
   string nm="SIRIUS_SL_"+(string)pid;
   if(GlobalVariableCheck(nm)) return GlobalVariableGet(nm);
   if(store && curSL>0){ GlobalVariableSet(nm,curSL); return curSL; }
   return 0;
}
double PlanRR(double open,double sl,double tp)
{
   if(sl>0&&tp>0&&MathAbs(open-sl)>0) return MathAbs(tp-open)/MathAbs(open-sl);
   return 2.0;
}
string OT(long t)
{
   switch((int)t)
   {
      case ORDER_TYPE_BUY_LIMIT: return "BUY LIMIT";
      case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT";
      case ORDER_TYPE_BUY_STOP: return "BUY STOP";
      case ORDER_TYPE_SELL_STOP: return "SELL STOP";
      case ORDER_TYPE_BUY_STOP_LIMIT: return "BUY STOP LIMIT";
      case ORDER_TYPE_SELL_STOP_LIMIT: return "SELL STOP LIMIT";
   }
   return "ORDER";
}

//--- closed trade JSON for a position id -------------------------------
string BuildTrade(ulong pid,string &note)
{
   note="";
   if(!HistorySelectByPosition(pid)) return "";
   int n=HistoryDealsTotal();
   double net=0,vol=0,open=0,sl=0,tp=0;
   string sym="",dir="BUY"; datetime ot=0; bool hasIn=false,hasOut=false; ulong inOrder=0;
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      long type=HistoryDealGetInteger(d,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY&&type!=DEAL_TYPE_SELL) continue;
      long en=HistoryDealGetInteger(d,DEAL_ENTRY);
      net+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_COMMISSION)
          +HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_FEE);
      if(en==DEAL_ENTRY_IN && !hasIn)
      {
         hasIn=true;
         sym=HistoryDealGetString(d,DEAL_SYMBOL);
         dir=(type==DEAL_TYPE_BUY)?"BUY":"SELL";
         ot=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
         open=HistoryDealGetDouble(d,DEAL_PRICE);
         vol=HistoryDealGetDouble(d,DEAL_VOLUME);
         inOrder=(ulong)HistoryDealGetInteger(d,DEAL_ORDER);
      }
      if(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_OUT_BY) hasOut=true;
   }
   if(!hasIn||!hasOut) return "";
   if(inOrder>0 && HistoryOrderSelect(inOrder))
   {
      sl=HistoryOrderGetDouble(inOrder,ORDER_SL);
      tp=HistoryOrderGetDouble(inOrder,ORDER_TP);
   }
   double isl=InitSL(pid,sl,false);   // первоначальный SL, запомненный роботом
   if(isl>0) sl=isl;
   double risk=RiskOf(sym,open,sl,vol);
   string res;
   if(risk>0) res=(MathAbs(net)<0.1*risk)?"BU":(net>0?"TP":"SL");
   else       res=(MathAbs(net)<1.0)?"BU":(net>0?"TP":"SL");
   double rr=PlanRR(open,sl,tp);
   if(sl<=0||tp<=0) rr=(risk>0&&net>0)?net/risk:2.0;
   string ic=(res=="TP")?ShortToString(0x2705):(res=="SL")?ShortToString(0x274C):ShortToString(0x26AA);
   note=ic+" "+res+" "+sym+" "+dir+"\nP/L: "+N2(net)+" | R: "+(risk>0?N2(net/risk):"-")+"\nAcc: "+(string)g_login;
   return StringFormat("{\"ticket\":%I64u,\"symbol\":\"%s\",\"dir\":\"%s\",\"result\":\"%s\",\"pnl\":%s,\"risk\":%s,\"rr\":%s,\"vol\":%s,\"open\":%s,\"sl\":%s,\"tp\":%s,\"date\":\"%s\",\"time\":\"%s\"}",
                       pid,sym,dir,res,N2(net),N2(risk),N2(rr),N2(vol),PR(sym,open),PR(sym,sl),PR(sym,tp),D(ot),H(ot));
}

//--- whole history -> batched messages ---------------------------------
void QueueHistory()
{
   if(!HistorySelect(0,TimeCurrent()+86400)) return;
   int n=HistoryDealsTotal(); ulong pids[]; double dep=0;
   for(int i=0;i<n;i++)
   {
      ulong d=HistoryDealGetTicket(i); if(d==0) continue;
      long type=HistoryDealGetInteger(d,DEAL_TYPE);
      if(type==DEAL_TYPE_BALANCE){ dep+=HistoryDealGetDouble(d,DEAL_PROFIT); continue; }
      long en=HistoryDealGetInteger(d,DEAL_ENTRY);
      if((type==DEAL_TYPE_BUY||type==DEAL_TYPE_SELL)&&(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_OUT_BY))
      {
         ulong pid=(ulong)HistoryDealGetInteger(d,DEAL_POSITION_ID);
         bool have=false; int m=ArraySize(pids);
         for(int k=m-1;k>=0;k--) if(pids[k]==pid){have=true;break;}
         if(!have){ ArrayResize(pids,m+1); pids[m]=pid; }
      }
   }
   string head=StringFormat("{\"k\":\"hist\",\"account_id\":%I64d,\"dep\":%s,\"t\":[",g_login,N2(dep));
   string cur="";
   for(int i=0;i<ArraySize(pids);i++)
   {
      string nt; string t=BuildTrade(pids[i],nt); if(t=="") continue;
      if(StringLen(head)+StringLen(cur)+StringLen(t)+4>3600){ Push(head+cur+"]}"); cur=""; }
      cur+=(cur==""?"":",")+t;
   }
   if(cur!="") Push(head+cur+"]}");
   Print("SiriusSync: сделок в истории: ",ArraySize(pids),", сообщений в очереди: ",ArraySize(g_q));
}

//--- snapshot: account + open positions + pending orders ---------------
void QueueSnapshot()
{
   string s=StringFormat("{\"k\":\"snap\",\"account_id\":%I64d,\"ts\":%I64d,\"cur\":\"%s\",\"bal\":%s,\"eq\":%s,\"mg\":%s,\"fr\":%s,\"pl\":%s,\"pos\":[",
      g_login,(long)TimeGMT(),AccountInfoString(ACCOUNT_CURRENCY),N2(AccountInfoDouble(ACCOUNT_BALANCE)),N2(AccountInfoDouble(ACCOUNT_EQUITY)),
      N2(AccountInfoDouble(ACCOUNT_MARGIN)),N2(AccountInfoDouble(ACCOUNT_MARGIN_FREE)),N2(AccountInfoDouble(ACCOUNT_PROFIT)));
   int tot=PositionsTotal(), cnt=0;
   for(int i=0;i<tot&&cnt<8;i++)
   {
      ulong tk=PositionGetTicket(i); if(tk==0) continue;
      string sym=PositionGetString(POSITION_SYMBOL);
      long ty=PositionGetInteger(POSITION_TYPE);
      double op=PositionGetDouble(POSITION_PRICE_OPEN), sl=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP);
      double vol=PositionGetDouble(POSITION_VOLUME), fl=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      ulong pid=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double isl=InitSL(pid,sl,true), slr=(isl>0?isl:sl);
      datetime pt=(datetime)PositionGetInteger(POSITION_TIME);
      string p=StringFormat("{\"ticket\":%I64u,\"symbol\":\"%s\",\"dir\":\"%s\",\"vol\":%s,\"open\":%s,\"sl\":%s,\"tp\":%s,\"fl\":%s,\"risk\":%s,\"rr\":%s,\"date\":\"%s\",\"time\":\"%s\"}",
         pid,sym,(ty==POSITION_TYPE_BUY?"BUY":"SELL"),N2(vol),PR(sym,op),PR(sym,sl),PR(sym,tp),N2(fl),
         N2(RiskOf(sym,op,slr,vol)),N2(PlanRR(op,slr,tp)),D(pt),H(pt));
      if(StringLen(s)+StringLen(p)>3700) break;
      s+=(cnt>0?",":"")+p; cnt++;
   }
   s+="]}";
   Push(s);

   string o=""; int oc=0, ot=OrdersTotal();
   for(int i=0;i<ot&&oc<15;i++)
   {
      ulong tk=OrderGetTicket(i); if(tk==0) continue;
      string sym=OrderGetString(ORDER_SYMBOL);
      string e=StringFormat("{\"t\":\"%s\",\"s\":\"%s\",\"v\":%s,\"p\":%s,\"sl\":%s,\"tp\":%s}",
         OT(OrderGetInteger(ORDER_TYPE)),sym,N2(OrderGetDouble(ORDER_VOLUME_CURRENT)),PR(sym,OrderGetDouble(ORDER_PRICE_OPEN)),
         PR(sym,OrderGetDouble(ORDER_SL)),PR(sym,OrderGetDouble(ORDER_TP)));
      o+=(oc>0?",":"")+e; oc++;
   }
   if(o!=g_lastOrds || TimeLocal()-g_lastOrdsTime>600)
   {
      Push(StringFormat("{\"k\":\"ords\",\"account_id\":%I64d,\"o\":[%s]}",g_login,o));
      g_lastOrds=o; g_lastOrdsTime=TimeLocal();
   }
}

//--- Firebase ----------------------------------------------------------
int FbReq(string method,string url,string json)
{
   char data[],res[]; string rh;
   int n=StringToCharArray(json,data,0,StringLen(json),CP_UTF8);
   ArrayResize(data,n);
   ResetLastError();
   return WebRequest(method,url,"Content-Type: application/json\r\n",10000,data,res,rh);
}
int SendFB(string json)
{
   string path="log"; bool put=false;
   if(StringFind(json,"\"k\":\"snap\"")>=0){ path="live/"+(string)g_login+"/snap"; put=true; }
   else if(StringFind(json,"\"k\":\"ords\"")>=0){ path="live/"+(string)g_login+"/ords"; put=true; }
   string url=FirebaseURL;
   if(StringSubstr(url,StringLen(url)-1,1)=="/") url=StringSubstr(url,0,StringLen(url)-1);
   url+="/sirius/"+SyncKey+"/"+path+".json";
   if(!put) return FbReq("POST",url,json);
   int c=FbReq("POST",url+"?x-http-method-override=PUT",json);
   if(c==200) return c;
   return FbReq("PUT",url,json);
}

//--- Telegram ----------------------------------------------------------
int SendTg(string text,string chat)
{
   string url="https://api.telegram.org/bot"+BotToken+"/sendMessage";
   string body="chat_id="+UrlEnc(chat)+"&text="+UrlEnc(text);
   char data[],res[]; string rh;
   int n=StringToCharArray(body,data,0,StringLen(body),CP_UTF8);
   ArrayResize(data,n);
   ResetLastError();
   return WebRequest("POST",url,"Content-Type: application/x-www-form-urlencoded\r\n",8000,data,res,rh);
}

//--- events ------------------------------------------------------------
int OnInit()
{
   if((FirebaseURL==""||SyncKey=="") && (BotToken==""||ChatID=="")){ Alert("SiriusSync: укажите FirebaseURL и SyncKey (или BotToken и ChatID)"); return INIT_PARAMETERS_INCORRECT; }
   g_login=AccountInfoInteger(ACCOUNT_LOGIN);
   string gv="SIRIUS_H_"+(string)g_login;
   if(SendHistory && (ResendHistory || !GlobalVariableCheck(gv))){ QueueHistory(); g_histPending=true; }
   EventSetTimer(2);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){ EventKillTimer(); }

void OnTradeTransaction(const MqlTradeTransaction &t,const MqlTradeRequest &r,const MqlTradeResult &res)
{
   g_dirty=true;
   if(t.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(t.deal))
   {
      long en=HistoryDealGetInteger(t.deal,DEAL_ENTRY);
      if(en==DEAL_ENTRY_OUT||en==DEAL_ENTRY_OUT_BY)
      {
         int m=ArraySize(g_closeQ); ArrayResize(g_closeQ,m+1);
         g_closeQ[m]=(ulong)HistoryDealGetInteger(t.deal,DEAL_POSITION_ID);
      }
   }
}

void OnTimer()
{
   //--- закрытые сделки (полностью закрытые позиции)
   for(int i=0;i<ArraySize(g_closeQ);i++)
   {
      ulong pid=g_closeQ[i];
      if(PositionSelectByTicket(pid)) continue; // частичное закрытие
      string note; string t=BuildTrade(pid,note);
      if(t!=""){ Push(StringFormat("{\"k\":\"hist\",\"account_id\":%I64d,\"ts\":%I64d,\"t\":[%s]}",g_login,(long)TimeGMT(),t)); if(NotifyChatID!=""&&BotToken!="") Push("~N~"+note); }
   }
   ArrayResize(g_closeQ,0);

   //--- снимок счёта
   int iv=(PositionsTotal()>0)?SnapshotSec:MathMax(SnapshotSec,60);
   if(ArraySize(g_q)<20 && TimeLocal()-g_lastSnap>=(g_dirty?10:iv))
   {
      QueueSnapshot(); g_lastSnap=TimeLocal(); g_dirty=false;
   }

   //--- отправка очереди (Firebase: до 6 за тик; Telegram: 1 в 4 сек)
   bool useFB=(FirebaseURL!=""&&SyncKey!="");
   for(int b=0; b<(useFB?6:1) && ArraySize(g_q)>0 && GetTickCount64()>=g_nextSend; b++)
   {
      string item=g_q[0]; bool isN=(StringSubstr(item,0,3)=="~N~"); if(isN) item=StringSubstr(item,3);
      bool viaFB=(useFB&&!isN);
      int code=viaFB?SendFB(item):SendTg(item,isN?NotifyChatID:ChatID);
      if(code==200){ ArrayRemove(g_q,0,1); g_nextSend=viaFB?0:GetTickCount64()+4000; }
      else if(code==-1)
      {
         Print("SiriusSync: WebRequest ошибка ",GetLastError(),". Добавьте ",(viaFB?FirebaseURL:"https://api.telegram.org")," в Сервис > Настройки > Советники > Разрешить WebRequest");
         g_nextSend=GetTickCount64()+30000; break;
      }
      else if(isN&&(code==400||code==403)){ ArrayRemove(g_q,0,1); Print("SiriusSync: NotifyChatID недоступен (HTTP ",code,"). Напишите /start боту-отправителю"); }
      else if(code==429){ g_nextSend=GetTickCount64()+20000; break; }
      else { Print("SiriusSync: ",(viaFB?"Firebase":"Telegram")," HTTP ",code," (проверьте URL/ключ/Rules или токен/ChatID)"); g_nextSend=GetTickCount64()+30000; break; }
   }
   if(g_histPending && ArraySize(g_q)==0)
   {
      GlobalVariableSet("SIRIUS_H_"+(string)g_login,1); g_histPending=false;
      Print("SiriusSync: история отправлена полностью");
   }
}
