//+------------------------------------------------------------------+
//| JournalExport.mq5                                                |
//| Export des positions clôturées vers JSON, sur demande            |
//|                                                                  |
//| Utilise FILE_COMMON → écrit dans Terminal/Common/Files/          |
//| (dossier partagé, accessible depuis le Mac sans chemin complexe) |
//+------------------------------------------------------------------+
#property copyright "Journal de Trading"
#property version   "1.0"
#property description "Export on-demand des trades clôturés — journal de trading"

static const string TRIGGER = "mt5_trigger.txt";
static const string OUTPUT  = "closed_trades.json";

//+------------------------------------------------------------------+
int OnInit()
  {
   EventSetTimer(1);
   Print("JournalExport: actif. En attente de trigger dans Common/Files…");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
  }

void OnTick() {}

//+------------------------------------------------------------------+
void OnTimer()
  {
   if(!FileIsExist(TRIGGER, FILE_COMMON))
      return;

   FileDelete(TRIGGER, FILE_COMMON);
   Print("JournalExport: trigger reçu — export en cours…");
   ExportClosedTrades();
  }

//+------------------------------------------------------------------+
void ExportClosedTrades()
  {
   if(!HistorySelect(0, TimeCurrent() + 86400))
     {
      Print("JournalExport: HistorySelect() échoué");
      return;
     }

   int total = HistoryDealsTotal();

   // Collecter les position IDs des deals OUT (positions clôturées)
   long posIds[];
   int  posCount = 0;

   for(int i = 0; i < total; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      long pid = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      bool found = false;
      for(int j = 0; j < posCount; j++)
         if(posIds[j] == pid) { found = true; break; }

      if(!found)
        {
         ArrayResize(posIds, posCount + 1);
         posIds[posCount++] = pid;
        }
     }

   // Écrire le JSON dans Common/Files
   int fh = FileOpen(OUTPUT, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE)
     {
      Print("JournalExport: impossible d'ouvrir ", OUTPUT);
      return;
     }

   FileWriteString(fh, "[\n");
   bool first = true;

   for(int p = 0; p < posCount; p++)
     {
      long  pid  = posIds[p];
      ulong tIn  = 0;
      ulong tOut = 0;

      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_POSITION_ID) != pid) continue;

         ENUM_DEAL_ENTRY e = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(e == DEAL_ENTRY_IN)  tIn  = ticket;
         if(e == DEAL_ENTRY_OUT) tOut = ticket;
        }

      if(tOut == 0) continue; // position encore ouverte

      string   sym    = HistoryDealGetString(tOut, DEAL_SYMBOL);
      double   vol    = HistoryDealGetDouble(tIn != 0 ? tIn : tOut, DEAL_VOLUME);
      datetime dtIn   = tIn != 0 ? (datetime)HistoryDealGetInteger(tIn,  DEAL_TIME) : 0;
      datetime dtOut  = (datetime)HistoryDealGetInteger(tOut, DEAL_TIME);
      double   pxIn   = tIn != 0 ? HistoryDealGetDouble(tIn,  DEAL_PRICE) : 0.0;
      double   pxOut  = HistoryDealGetDouble(tOut, DEAL_PRICE);
      double   profit = HistoryDealGetDouble(tOut, DEAL_PROFIT);
      double   comm   = (tIn != 0 ? HistoryDealGetDouble(tIn,  DEAL_COMMISSION) : 0.0)
                        + HistoryDealGetDouble(tOut, DEAL_COMMISSION);
      double   swap   = (tIn != 0 ? HistoryDealGetDouble(tIn,  DEAL_SWAP) : 0.0)
                        + HistoryDealGetDouble(tOut, DEAL_SWAP);
      double   net    = profit + comm + swap;

      string dir;
      if(tIn != 0)
         dir = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(tIn, DEAL_TYPE) == DEAL_TYPE_BUY) ? "LONG" : "SHORT";
      else
         dir = ((ENUM_DEAL_TYPE)HistoryDealGetInteger(tOut, DEAL_TYPE) == DEAL_TYPE_SELL) ? "LONG" : "SHORT";

      string sIn  = tIn != 0 ? TimeToString(dtIn,  TIME_DATE | TIME_SECONDS) : "";
      string sOut = TimeToString(dtOut, TIME_DATE | TIME_SECONDS);

      if(!first) FileWriteString(fh, ",\n");
      first = false;

      FileWriteString(fh, StringFormat(
                        "  {\"ticket\":%d,\"symbol\":\"%s\",\"direction\":\"%s\","
                        "\"volume\":%.5f,\"open_time\":\"%s\",\"close_time\":\"%s\","
                        "\"open_price\":%.5f,\"close_price\":%.5f,"
                        "\"profit\":%.2f,\"commission\":%.2f,\"swap\":%.2f,\"net_pnl\":%.2f}",
                        (int)pid, sym, dir, vol,
                        sIn, sOut, pxIn, pxOut,
                        profit, comm, swap, net
                     ));
     }

   FileWriteString(fh, "\n]");
   FileClose(fh);
   Print("JournalExport: ", posCount, " positions exportées → Common/Files/", OUTPUT);
  }
//+------------------------------------------------------------------+
