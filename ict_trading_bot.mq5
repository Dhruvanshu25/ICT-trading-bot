//+------------------------------------------------------------------+
//|                                              Ict_trading_bot.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

#define clrup clrLime
#define clrdown clrRed

input bool UseSessionFilter = true;
input int LondonOpenHour = 8;    // London open (GMT/UTC)
input int LondonCloseHour = 16;  // London close
input int NYOpenHour = 13;       // NY open (GMT/UTC)
input int NYCloseHour = 21;      // NY close
input bool AvoidAsianSession = true;
input int    Asiastarthour    = 3;
input int    asiastartmin     = 0;
input int    asiaendhour      = 7;
input int    asiaendmin       = 0;
input double ImpulseMultiplier = 2.0;   // impulse vs candle before it
input double MaxOBBodyRatio    = 0.5;   // OB must be small vs impulse
input int    OBExtendBars      = 50;    // rectangle extension
input int    SLBufferPoints    = 100;
input double RiskPercent       = 0.5;   // % per trade
input double MinZonePenetration = 0.3;
input bool   UseNewsFilter     = true;  // Block trading around high impact news
input int    NewsMinutesBefore = 10;    // Minutes to block before news
input int    NewsMinutesAfter  = 10;    // Minutes to block after news
input bool   UsePDFilter       = true;  // Filter zones by Premium/Discount

// Asia box
double asiahigh = 0.0;
double asialow  = 0.0;
datetime lastAsiaSessionEnd = 0;

bool asiaHighTaken = false;
bool asiaLowTaken  = false;
bool asiaSessionActive = false;

bool tradedToday = false;
int  lastTradeDay = -1;

// Inducement detection
bool inducementDetectedLong = false;
bool inducementDetectedShort = false;
datetime lastInducementTime = 0;
input int InducementValidBars = 15;    // How long inducement stays valid
input bool RequireInducement = false;  // Require inducement for entry (toggle on/off)

//----------------- SWINGS + TREND 15M / 1H / 4H --------------------//

bool inPremium  = false;
bool inDiscount = false;

input double PreferOBDistancePips = 100;

string touchedLongZoneName = "";
string touchedShortZoneName = "";

bool fvgExitConfirmedLong = false;
bool fvgExitConfirmedShort = false;

int longTouchBar  = -1;
int shortTouchBar = -1;

//FVG
bool fvgexist;
string totalFVG5m[];
string totalFVG15m[];
int barindices15m[];
datetime barTimes15m[];
bool isFVG15m = false;

bool longZoneTouched  = false;
bool shortZoneTouched = false;

// Track last zone touched direction to suppress counter-trend entries
// -1 = last touch was bearish zone, +1 = last touch was bullish zone, 0 = none
int  lastTouchDirection = 0;
string lastAdverseZoneName = "";  // the bearish/bullish zone suppressing entries

double touchedFvgLow = 0;
double touchedFvgHigh = 0;
double touchedObLow = 0;
double touchedObHigh = 0;

// 15m
double   swingHighs_15m[];
datetime swingHighTimes_15m[];
double   swingLows_15m[];
datetime swingLowTimes_15m[];

double swingH_15m = -1.0;
double swingL_15m = -1.0;

bool uptrend_15m   = false;
bool downtrend_15m = false;
int structureDir_15m = 0; 
// +1 = bullish structure
// -1 = bearish structure
double lastProcessedSwingH_15m = -1.0;
double lastProcessedSwingL_15m = -1.0;

// 1H
double   swingHighs_1h[];
datetime swingHighTimes_1h[];
double   swingLows_1h[];
datetime swingLowTimes_1h[];

double swingH_1h = -1.0;
double swingL_1h = -1.0;

bool uptrend_1h   = false;
bool downtrend_1h = false;
double lastProcessedSwingH_1h = -1.0;
double lastProcessedSwingL_1h = -1.0;

// 4H (only trend, no arrays)
double swingH_4h = -1.0;
double swingL_4h = -1.0;
double lastProcessedSwingH_4h = -1.0;
double lastProcessedSwingL_4h = -1.0;
bool uptrend_4h   = false;
bool downtrend_4h = false;

input int    LookbackBars        = 60;
input int    StructureLookback   = 10;
input int    ConsolidationBars   = 5;
input double DisplacementMult    = 2.5;
string   totalOB15m[];
datetime obTimes15m[];
string   totalOB1h[];
datetime obTimes1h[];

// ---- 1M CHoCH inputs & state ----
input int Swing1mLength = 3;   // bars each side for 1M swing detection

bool   waitingFor1mChochLong  = false;
bool   waitingFor1mChochShort = false;

// tracked 1M swings — reset when touch is armed, updated every 1M bar
double swingH_1m              = -1.0;
double swingL_1m              = -1.0;
double lastProcessedSwingH_1m = -1.0;
double lastProcessedSwingL_1m = -1.0;

double chochSL_Long  = 0.0;
double chochSL_Short = 0.0;

// Partial close tracking
bool   partialClosedLong  = false;
bool   partialClosedShort = false;


int OnInit(){
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
}

//+------------------------------------------------------------------+
//| Helper: get equilibrium from 3-bar peak/trough on 1H            |
//+------------------------------------------------------------------+
double GetPDEquilibrium()
{
   double pdHigh = 0, pdLow = 0;

   for(int x = 1; x <= 100 && pdHigh == 0; x++)
   {
      double h = iHigh(_Symbol, PERIOD_H1, x);
      if(h == 0) continue;
      bool isPeak = true;
      for(int j = 1; j <= 3; j++)
      {
         if(h <= iHigh(_Symbol, PERIOD_H1, x+j) ||
            h <  iHigh(_Symbol, PERIOD_H1, x-j))
         { isPeak = false; break; }
      }
      if(isPeak) pdHigh = h;
   }

   for(int x = 1; x <= 100 && pdLow == 0; x++)
   {
      double l = iLow(_Symbol, PERIOD_H1, x);
      if(l == 0) continue;
      bool isTrough = true;
      for(int j = 1; j <= 3; j++)
      {
         if(l >= iLow(_Symbol, PERIOD_H1, x+j) ||
            l >  iLow(_Symbol, PERIOD_H1, x-j))
         { isTrough = false; break; }
      }
      if(isTrough) pdLow = l;
   }

   if(pdHigh == 0 || pdLow == 0 || pdHigh <= pdLow) return 0;

   return (pdHigh + pdLow) / 2.0;
}

void OnTick(){

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   datetime currentTime = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(currentTime, dt);
   
   asiaSessionActive =
   (dt.hour > Asiastarthour || (dt.hour == Asiastarthour && dt.min >= asiastartmin)) &&
   (dt.hour < asiaendhour   || (dt.hour == asiaendhour   && dt.min <  asiaendmin));

   // ----------- ASIA RANGE CALC + DRAW ---------------------------//
   if(dt.hour > asiaendhour || (dt.hour == asiaendhour && dt.min >= asiaendmin))
   {
      MqlDateTime sessionEnd;
      sessionEnd.year = dt.year;
      sessionEnd.mon  = dt.mon;
      sessionEnd.day  = dt.day;
      sessionEnd.hour = asiaendhour;
      sessionEnd.min  = asiaendmin;
      sessionEnd.sec  = 0;
      datetime sesEnd = StructToTime(sessionEnd);

      MqlDateTime sessionStart;
      sessionStart.year = dt.year;
      sessionStart.mon  = dt.mon;
      sessionStart.day  = dt.day;
      sessionStart.hour = Asiastarthour;
      sessionStart.min  = asiastartmin;
      sessionStart.sec  = 0;
      datetime sesStart = StructToTime(sessionStart);

      if(sesEnd != lastAsiaSessionEnd)
      {
         int totalbars = Bars(_Symbol, PERIOD_M5);
         MqlRates rates[];
         ArraySetAsSeries(rates, false);
         int copied = CopyRates(_Symbol, PERIOD_M5, 0, totalbars, rates);

         double highValue = -DBL_MAX;
         double lowValue  = DBL_MAX;

         for(int i = 0; i < copied; i++)
         {
            if(rates[i].time >= sesStart && rates[i].time <= sesEnd)
            {
               if(rates[i].high > highValue)
                  highValue = rates[i].high;
               if(rates[i].low < lowValue)
                  lowValue = rates[i].low;
            }
         }
         if(lowValue != DBL_MAX && highValue != -DBL_MAX)
         {
            asiahigh = highValue;
            asialow  = lowValue;
         }

         lastAsiaSessionEnd = sesEnd;
         AsiaRangeBox(sesStart, sesEnd);
      }
   }
   
   double prevHigh = iHigh(_Symbol, PERIOD_M15, 1);
   double prevLow  = iLow (_Symbol, PERIOD_M15, 1);

   if(prevHigh > asiahigh)
   {
      asiaHighTaken = true;
      asiaLowTaken  = false;
   }

   if(prevLow < asialow)
   {
      asiaLowTaken  = true;
      asiaHighTaken = false;
   }
   // ----------- NEW BAR DETECTORS (15m / 1H / 4H) ----------------//
   
   // ---- 1M new bar detector ----
   static int prevBars_1m = 0;
   int currBars_1m = iBars(_Symbol, PERIOD_M1);
   bool isNewBar_1m = (currBars_1m != prevBars_1m);
   if(isNewBar_1m)
      prevBars_1m = currBars_1m;

   // ---- 5M new bar detector ----
   static int prevBars_5m = 0;
   int currBars_5m = iBars(_Symbol, PERIOD_M5);
   bool isNewBar_5m = (currBars_5m != prevBars_5m);
   if(isNewBar_5m)
      prevBars_5m = currBars_5m;
      
   // 15m
   static int prevBars_15m = 0;
   int currBars_15m = iBars(_Symbol, PERIOD_M15);
   bool isNewbar_15m = (currBars_15m != prevBars_15m);
   if(isNewbar_15m)
      prevBars_15m = currBars_15m;

   if(isNewbar_15m){
   CheckICTOBMitigation_M15();
   }

   // 1H
   static int prevBars_1h = 0;
   int currBars_1h = iBars(_Symbol, PERIOD_H1);
   bool isNewbar_1h = (currBars_1h != prevBars_1h);
   if(isNewbar_1h)
      prevBars_1h = currBars_1h;
   
   if(isNewbar_1h){
   CheckICTOBMitigation_H1();
   DrawPremiumDiscount();
   }

   // 4H
   static int prevBars_4h = 0;
   int currBars_4h = iBars(_Symbol, PERIOD_H4);
   bool isNewbar_4h = (currBars_4h != prevBars_4h);
   if(isNewbar_4h)
      prevBars_4h = currBars_4h;

   // ------------------- 15M SWING + FVG --------------------------//
   if(isNewbar_15m && currBars_15m > 20)
   {
      const int length = 7;
      int curr_bar = length;
      bool isSwingHigh = true, isSwingLow = true;

      for(int i = 1; i <= length; i++)
      {
         int right_index = curr_bar - i;
         int left_index  = curr_bar + i;

         if((iHigh(_Symbol, PERIOD_M15, curr_bar) <= iHigh(_Symbol, PERIOD_M15, right_index)) ||
            (iHigh(_Symbol, PERIOD_M15, curr_bar) <  iHigh(_Symbol, PERIOD_M15, left_index)))
            isSwingHigh = false;

         if((iLow(_Symbol, PERIOD_M15, curr_bar) >= iLow(_Symbol, PERIOD_M15, right_index)) ||
            (iLow(_Symbol, PERIOD_M15, curr_bar) >  iLow(_Symbol, PERIOD_M15, left_index)))
            isSwingLow = false;
      }

      if(isSwingHigh)
      {
         swingH_15m = iHigh(_Symbol, PERIOD_M15, curr_bar);
         datetime swingTime = iTime(_Symbol, PERIOD_M15, curr_bar);

         bool alreadyExists = false;
         for(int j = 0; j < ArraySize(swingHighs_15m); j++)
         {
            if(swingHighs_15m[j] == swingH_15m && swingHighTimes_15m[j] == swingTime)
            {
               alreadyExists = true;
               break;
            }
         }
         if(!alreadyExists)
         {
            SwingPoints("15m_H_" + TimeToString(swingTime), swingTime, swingH_15m, 226, 1, clrYellow);
            int n = ArraySize(swingHighs_15m);
            ArrayResize(swingHighs_15m, n + 1);
            ArrayResize(swingHighTimes_15m, n + 1);
            swingHighs_15m[n]      = swingH_15m;
            swingHighTimes_15m[n]  = swingTime;
         }
      }

      if(isSwingLow)
      {
         swingL_15m = iLow(_Symbol, PERIOD_M15, curr_bar);
         datetime swingTime = iTime(_Symbol, PERIOD_M15, curr_bar);

         bool alreadyExists = false;
         for(int j = 0; j < ArraySize(swingLows_15m); j++)
         {
            if(swingLows_15m[j] == swingL_15m && swingLowTimes_15m[j] == swingTime)
            {
               alreadyExists = true;
               break;
            }
         }
         if(!alreadyExists)
         {
            SwingPoints("15m_L_" + TimeToString(swingTime), swingTime, swingL_15m, 225, -1, clrYellow);
            int n = ArraySize(swingLows_15m);
            ArrayResize(swingLows_15m, n + 1);
            ArrayResize(swingLowTimes_15m, n + 1);
            swingLows_15m[n]     = swingL_15m;
            swingLowTimes_15m[n] = swingTime;
         }
      }

      double lastClose15 = iClose(_Symbol, PERIOD_M15, 1);

      // ===== CHOCH DOWN (break low while in uptrend) =====
      if(uptrend_15m &&
         swingL_15m > 0 &&
         swingL_15m != lastProcessedSwingL_15m &&
         lastClose15 < swingL_15m)
      {
         int low_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iLow(_Symbol, PERIOD_M15, i) == swingL_15m)
            {
               low_index = i;
               break;
            }
         }

         BOS("15m_CHOCH_DN_" + TimeToString(iTime(_Symbol, PERIOD_M15, low_index)),
             iTime(_Symbol, PERIOD_M15, low_index),
             swingL_15m,
             iTime(_Symbol, PERIOD_M15, 1),
             swingL_15m, -1, "CHOCH", clrOrange);

         downtrend_15m = true;
         uptrend_15m   = false;
         structureDir_15m = -1;
         lastProcessedSwingL_15m = swingL_15m;
         
         longZoneTouched = false;
         touchedObLow = 0;
         touchedFvgLow = 0;
         touchedLongZoneName = "";
         fvgExitConfirmedLong = false;
         longTouchBar = -1;
         inducementDetectedLong = false;
         lastInducementTime = 0;
         waitingFor1mChochLong = false;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Long = 0.0;
         DetectICT_OB(PERIOD_M15, "M15",-1);
         swingL_15m = -1.0;
      }

      // ===== CHOCH UP (break high while in downtrend) =====
      if(downtrend_15m &&
         swingH_15m > 0 &&
         swingH_15m != lastProcessedSwingH_15m &&
         lastClose15 > swingH_15m)
      {
         int high_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iHigh(_Symbol, PERIOD_M15, i) == swingH_15m)
            {
               high_index = i;
               break;
            }
         }

         BOS("15m_CHOCH_UP_" + TimeToString(iTime(_Symbol, PERIOD_M15, high_index)),
             iTime(_Symbol, PERIOD_M15, high_index),
             swingH_15m,
             iTime(_Symbol, PERIOD_M15, 1),
             swingH_15m, 1, "CHOCH", clrOrange);

         uptrend_15m   = true;
         downtrend_15m = false;
         structureDir_15m = 1;
         lastProcessedSwingH_15m = swingH_15m;
         inducementDetectedShort = false;
         lastInducementTime = 0;
         shortZoneTouched = false;
         touchedObHigh = 0;
         touchedFvgHigh = 0;
         touchedShortZoneName = "";
         fvgExitConfirmedShort = false;
         shortTouchBar = -1;
         waitingFor1mChochShort = false;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Short = 0.0;
         DetectICT_OB(PERIOD_M15, "M15",1);
         swingH_15m = -1.0;
      }

      // ===== BOS UP =====
      if(swingH_15m > 0 &&
         swingH_15m != lastProcessedSwingH_15m &&
         lastClose15 > swingH_15m && !downtrend_15m)
      {
         int high_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iHigh(_Symbol, PERIOD_M15, i) == swingH_15m)
            {
               high_index = i;
               break;
            }
         }
      
         BOS("15m_BOS_UP_" + TimeToString(iTime(_Symbol, PERIOD_M15, high_index)),
             iTime(_Symbol, PERIOD_M15, high_index),
             swingH_15m,
             iTime(_Symbol, PERIOD_M15, 1),
             swingH_15m, 1, "BOS", clrWhite);
      
         uptrend_15m     = true;
         downtrend_15m   = false;
         structureDir_15m = 1;
         
         shortZoneTouched = false;
         touchedObHigh = 0;
         touchedFvgHigh = 0;
         touchedShortZoneName = "";
         fvgExitConfirmedShort = false;
         shortTouchBar = -1;
         inducementDetectedShort = false;
         lastInducementTime = 0;
         waitingFor1mChochShort = false;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Short = 0.0;
         lastProcessedSwingH_15m = swingH_15m;
         DetectICT_OB(PERIOD_M15, "M15", 1);
         swingH_15m = -1.0;
      }

      // ===== BOS DOWN =====
      if(swingL_15m > 0 &&
         swingL_15m != lastProcessedSwingL_15m &&
         lastClose15 < swingL_15m && !uptrend_15m)
      {
         int low_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iLow(_Symbol, PERIOD_M15, i) == swingL_15m)
            {
               low_index = i;
               break;
            }
         }
      
         BOS("15m_BOS_DN_" + TimeToString(iTime(_Symbol, PERIOD_M15, low_index)),
             iTime(_Symbol, PERIOD_M15, low_index),
             swingL_15m,
             iTime(_Symbol, PERIOD_M15, 1),
             swingL_15m, -1, "BOS", clrWhite);
      
         downtrend_15m   = true;
         uptrend_15m     = false;
         structureDir_15m = -1;
         inducementDetectedLong = false;
         lastInducementTime = 0;
         longZoneTouched = false;
         touchedObLow = 0;
         touchedFvgLow = 0;
         touchedLongZoneName = "";
         fvgExitConfirmedLong = false;
         longTouchBar = -1;
         waitingFor1mChochLong = false;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Long = 0.0;
         lastProcessedSwingL_15m = swingL_15m;
         DetectICT_OB(PERIOD_M15, "M15", -1);
         swingL_15m = -1.0;
      }

      //fvg 15m
      for(int i = 0;i<= 20; i++){
         
         //bullish fvg
         double low0 = iLow(_Symbol,PERIOD_M15,i);
         double high2 = iHigh(_Symbol,PERIOD_M15,i+2);
         double gap1  = NormalizeDouble((low0-high2)/_Point,_Digits);
         
         //bearish fvg 
         double high0 = iHigh(_Symbol,PERIOD_M15,i);
         double low2 = iLow(_Symbol,PERIOD_M15,i+2);
         double gap2  =NormalizeDouble ((low2-high0)/_Point,_Digits);
         
         bool fvgup = low0 > high2 && gap1 > 300;
         bool fvgdown = low2 > high0 && gap2 > 300;
         
         if(i==0) continue;
         if(fvgup || fvgdown){
            
            datetime time1 = iTime(_Symbol,PERIOD_M15,i+2);
            datetime time2 = time1 + PeriodSeconds(PERIOD_M15)*20;
            string fvgname = "name" + "("+TimeToString(time1)+")";
            double price1 = fvgup ? high2 : high0;
            double price2 = fvgup ? low0 : low2;
            color fvgclr = fvgup ? clrup : clrdown;
            Rect(fvgname,time1,price1,time2,price2,fvgclr);
            ArrayResize(totalFVG15m,ArraySize(totalFVG15m)+1);
            totalFVG15m[ArraySize(totalFVG15m)-1] = fvgname;
            ArrayResize(barTimes15m,ArraySize(barTimes15m)+1);
            barTimes15m[ArraySize(barTimes15m)-1] = time1; 
             
         }
      } 

      for(int j = ArraySize(totalFVG15m)-1; j >= 0; j--)
      {
         string objname = totalFVG15m[j];
         bool mitigated = false;

         double p0 = ObjectGetDouble(0, objname, OBJPROP_PRICE, 0);
         double p1 = ObjectGetDouble(0, objname, OBJPROP_PRICE, 1);
         double fvgLow  = MathMin(p0, p1);
         double fvgHigh = MathMax(p0, p1);

         color fvgColor = (color)ObjectGetInteger(0, objname, OBJPROP_COLOR);
         datetime fvgTime = barTimes15m[j];

         int fvgBar = iBarShift(_Symbol, PERIOD_M15, fvgTime, false);
         if(fvgBar < 0)
            continue;

         int mitigationStartBar = fvgBar - 3;
         if(mitigationStartBar <= 1)
            continue;

         for(int k = mitigationStartBar; k >= 1; k--)
         {
            if(fvgColor == clrup)
            {
               if(iLow(_Symbol, PERIOD_M15, k) <= fvgLow)
               {
                  mitigated = true;
                  break;
               }
            }
            else if(fvgColor == clrdown)
            {
               if(iHigh(_Symbol, PERIOD_M15, k) >= fvgHigh)
               {
                  mitigated = true;
                  break;
               }
            }
         }

         if(mitigated)
         {
            ObjectDelete(0, objname);
            ArrayRemove(totalFVG15m, j, 1);
            ArrayRemove(barTimes15m, j, 1);
         }
      }

      DetectInducement();
   }

   // ------------------- 1H SWING + TREND + OB ---------------------//
   if(isNewbar_1h && currBars_1h > 20)
   {
      const int length_1h = 7;
      int curr_bar_1h = length_1h;
      bool isSwingHigh_1h = true, isSwingLow_1h = true;

      for(int i = 1; i <= length_1h; i++)
      {
         int right_index = curr_bar_1h - i;
         int left_index  = curr_bar_1h + i;

         if((iHigh(_Symbol, PERIOD_H1, curr_bar_1h) <= iHigh(_Symbol, PERIOD_H1, right_index)) ||
            (iHigh(_Symbol, PERIOD_H1, curr_bar_1h) <  iHigh(_Symbol, PERIOD_H1, left_index)))
            isSwingHigh_1h = false;

         if((iLow(_Symbol, PERIOD_H1, curr_bar_1h) >= iLow(_Symbol, PERIOD_H1, right_index)) ||
            (iLow(_Symbol, PERIOD_H1, curr_bar_1h) >  iLow(_Symbol, PERIOD_H1, left_index)))
            isSwingLow_1h = false;
      }

      if(isSwingHigh_1h)
      {
         swingH_1h = iHigh(_Symbol, PERIOD_H1, curr_bar_1h);
         datetime swingTime = iTime(_Symbol, PERIOD_H1, curr_bar_1h);

         bool alreadyExists = false;
         for(int j = 0; j < ArraySize(swingHighs_1h); j++)
         {
            if(swingHighs_1h[j] == swingH_1h && swingHighTimes_1h[j] == swingTime)
            {
               alreadyExists = true;
               break;
            }
         }
         if(!alreadyExists)
         {
            SwingPoints("1h_H_" + TimeToString(swingTime), swingTime, swingH_1h, 226, 1, clrAqua);
            int n = ArraySize(swingHighs_1h);
            ArrayResize(swingHighs_1h, n + 1);
            ArrayResize(swingHighTimes_1h, n + 1);
            swingHighs_1h[n]     = swingH_1h;
            swingHighTimes_1h[n] = swingTime;
         }
      }

      if(isSwingLow_1h)
      {
         swingL_1h = iLow(_Symbol, PERIOD_H1, curr_bar_1h);
         datetime swingTime = iTime(_Symbol, PERIOD_H1, curr_bar_1h);

         bool alreadyExists = false;
         for(int j = 0; j < ArraySize(swingLows_1h); j++)
         {
            if(swingLows_1h[j] == swingL_1h && swingLowTimes_1h[j] == swingTime)
            {
               alreadyExists = true;
               break;
            }
         }
         if(!alreadyExists)
         {
            SwingPoints("1h_L_" + TimeToString(swingTime), swingTime, swingL_1h, 225, -1, clrAqua);
            int n = ArraySize(swingLows_1h);
            ArrayResize(swingLows_1h, n + 1);
            ArrayResize(swingLowTimes_1h, n + 1);
            swingLows_1h[n]     = swingL_1h;
            swingLowTimes_1h[n] = swingTime;
         }
      }
      double lastClose1H = iClose(_Symbol, PERIOD_H1, 1);

      // ===== CHOCH DOWN =====
      if(uptrend_1h &&
         swingL_1h > 0 &&
         swingL_1h != lastProcessedSwingL_1h &&
         lastClose1H < swingL_1h)
      {
         int low_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iLow(_Symbol, PERIOD_H1, i) == swingL_1h)
            {
               low_index = i;
               break;
            }
         }

         BOS("1H_CHOCH_DN_" + TimeToString(iTime(_Symbol, PERIOD_H1, low_index)),
             iTime(_Symbol, PERIOD_H1, low_index),
             swingL_1h,
             iTime(_Symbol, PERIOD_H1, 1),
             swingL_1h, -1, "CHOCH", clrOrange);

         downtrend_1h = true;
         uptrend_1h   = false;
         // Reset lastTouchDirection on 1H trend change
         lastTouchDirection = 0;
         lastAdverseZoneName = "";
         lastProcessedSwingL_1h = swingL_1h;
         DetectICT_OB(PERIOD_H1, "H1",-1);
         swingL_1h = -1.0;
      }

      // ===== CHOCH UP =====
      if(downtrend_1h &&
         swingH_1h > 0 &&
         swingH_1h != lastProcessedSwingH_1h &&
         lastClose1H > swingH_1h)
      {
         int high_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iHigh(_Symbol, PERIOD_H1, i) == swingH_1h)
            {
               high_index = i;
               break;
            }
         }

         BOS("1H_CHOCH_UP_" + TimeToString(iTime(_Symbol, PERIOD_H1, high_index)),
             iTime(_Symbol, PERIOD_H1, high_index),
             swingH_1h,
             iTime(_Symbol, PERIOD_H1, 1),
             swingH_1h, 1, "CHOCH", clrOrange);

         uptrend_1h   = true;
         downtrend_1h = false;
         // Reset lastTouchDirection on 1H trend change
         lastTouchDirection = 0;
         lastAdverseZoneName = "";
         lastProcessedSwingH_1h = swingH_1h;
         DetectICT_OB(PERIOD_H1, "H1",1);
         swingH_1h = -1.0;
      }

      // ===== BOS UP =====
      if(swingH_1h > 0 &&
         swingH_1h != lastProcessedSwingH_1h &&
         lastClose1H > swingH_1h &&
         !downtrend_1h)
      {
         int high_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iHigh(_Symbol, PERIOD_H1, i) == swingH_1h)
            {
               high_index = i;
               break;
            }
         }

         BOS("1H_BOS_UP_" + TimeToString(iTime(_Symbol, PERIOD_H1, high_index)),
             iTime(_Symbol, PERIOD_H1, high_index),
             swingH_1h,
             iTime(_Symbol, PERIOD_H1, 1),
             swingH_1h, 1, "BOS", clrLime);

         uptrend_1h   = true;
         downtrend_1h = false;
         // Reset lastTouchDirection on 1H trend change
         lastTouchDirection = 0;
         lastAdverseZoneName = "";
         lastProcessedSwingH_1h = swingH_1h;
         DetectICT_OB(PERIOD_H1, "H1",1);
         swingH_1h = -1.0;
      }

      // ===== BOS DOWN =====
      if(swingL_1h > 0 &&
         swingL_1h != lastProcessedSwingL_1h &&
         lastClose1H < swingL_1h &&
         !uptrend_1h)
      {
         int low_index = 0;
         for(int i = 0; i <= 100; i++)
         {
            if(iLow(_Symbol, PERIOD_H1, i) == swingL_1h)
            {
               low_index = i;
               break;
            }
         }

         BOS("1H_BOS_DN_" + TimeToString(iTime(_Symbol, PERIOD_H1, low_index)),
             iTime(_Symbol, PERIOD_H1, low_index),
             swingL_1h,
             iTime(_Symbol, PERIOD_H1, 1),
             swingL_1h, -1, "BOS", clrLime);

         downtrend_1h = true;
         uptrend_1h   = false;
         // Reset lastTouchDirection on 1H trend change
         lastTouchDirection = 0;
         lastAdverseZoneName = "";
         lastProcessedSwingL_1h = swingL_1h;
         DetectICT_OB(PERIOD_H1, "H1",-1);
         swingL_1h = -1.0;
      }
   }

   // ------------------- 4H SWING+TREND (BIAS) ---------------------//
   if(isNewbar_4h && currBars_4h > 20)
   {
      const int length_4h = 10;
      int curr_bar_4h = length_4h;
      bool isSwingHigh_4h = true, isSwingLow_4h = true;

      for(int i = 1; i <= length_4h; i++)
      {
         int right_index = curr_bar_4h - i;
         int left_index  = curr_bar_4h + i;

         if((iHigh(_Symbol, PERIOD_H4, curr_bar_4h) <= iHigh(_Symbol, PERIOD_H4, right_index)) ||
            (iHigh(_Symbol, PERIOD_H4, curr_bar_4h) <  iHigh(_Symbol, PERIOD_H4, left_index)))
            isSwingHigh_4h = false;

         if((iLow(_Symbol, PERIOD_H4, curr_bar_4h) >= iLow(_Symbol, PERIOD_H4, right_index)) ||
            (iLow(_Symbol, PERIOD_H4, curr_bar_4h) >  iLow(_Symbol, PERIOD_H4, left_index)))
            isSwingLow_4h = false;
      }

      if(isSwingHigh_4h)
         swingH_4h = iHigh(_Symbol, PERIOD_H4, curr_bar_4h);

      if(isSwingLow_4h)
         swingL_4h = iLow(_Symbol, PERIOD_H4, curr_bar_4h);

      double lastClose4H = iClose(_Symbol, PERIOD_H4, 1);

      if(swingH_4h > 0 && swingH_4h != lastProcessedSwingH_4h)
      {
         if(lastClose4H > swingH_4h)
         {
            uptrend_4h   = true;
            downtrend_4h = false;
            lastProcessedSwingH_4h = swingH_4h;
            swingH_4h = -1.0;
         }
      }

      if(swingL_4h > 0 && swingL_4h != lastProcessedSwingL_4h)
      {
         if(lastClose4H < swingL_4h)
         {
            downtrend_4h = true;
            uptrend_4h   = false;
            lastProcessedSwingL_4h = swingL_4h;
            swingL_4h = -1.0;
         }
      }
   }

   // ---- daily reset ----
   MqlDateTime td;
   TimeToStruct(TimeCurrent(), td);
   
   if(td.day != lastTradeDay)
   {
      tradedToday = false;
      lastTradeDay = td.day;
   }
      
   // ---- partial close management ----
   ManagePartials();

   // ---- hard block ----
   if(tradedToday || HasOpenPosition())
      return;
   
   bool longBias  =  uptrend_1h;
   bool shortBias =  downtrend_1h;
   
   Print("LONG CHECK | up15=", uptrend_15m,
      " up1H=", uptrend_1h,
      " bias=", (uptrend_15m && uptrend_1h));

// ==================== LONG BIAS BLOCK ====================
if(longBias && isNewBar_5m)
{
   if(!IsValidTradingTime())
      return;

   double high15 = iHigh(_Symbol, PERIOD_M15, 1);
   double low15  = iLow (_Symbol, PERIOD_M15, 1);

   // -------- INVALIDATION --------
   if(longZoneTouched)
   {
      if(ObjectFind(0, touchedLongZoneName) < 0)
      {
         longZoneTouched = false;
         touchedFvgLow = 0;
         touchedObLow = 0;
         touchedLongZoneName = "";
         fvgExitConfirmedLong = false;
         longTouchBar = -1;
         waitingFor1mChochLong = false;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Long = 0.0;
         return;
      }
   }

   // -------- ADVERSE ZONE MITIGATION CHECK --------
   // If suppressed by a bearish zone, check if it's been mitigated (deleted)
   if(lastTouchDirection == -1 && lastAdverseZoneName != "")
   {
      if(ObjectFind(0, lastAdverseZoneName) < 0)
      {
         lastTouchDirection = 0;
         lastAdverseZoneName = "";
         Print("Adverse bearish zone mitigated - longs re-enabled");
      }
   }

   // -------- SCAN FOR BEARISH ZONE TOUCH (suppress longs) --------
   // This runs BEFORE bullish zone scan so red zones always register first
   if(!longZoneTouched && lastTouchDirection != -1)
   {
      // Check bearish 15M OBs
      for(int i = 0; i < ArraySize(totalOB15m); i++)
      {
         string nm = totalOB15m[i];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrRed) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);

         if(!(high15 >= zLow && low15 <= zHigh)) continue;

         // Price touched a bearish OB — suppress longs
         lastTouchDirection  = -1;
         lastAdverseZoneName = nm;
         Print("*** BEARISH OB TOUCHED in uptrend - longs suppressed: ", nm);
         break;
      }

      // Check bearish 15M FVGs
      if(lastTouchDirection != -1)
      {
         for(int j = 0; j < ArraySize(totalFVG15m); j++)
         {
            string nm = totalFVG15m[j];
            if(ObjectFind(0,nm) < 0) continue;
            if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrRed) continue;

            double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
            double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
            double zLow  = MathMin(p0,p1);
            double zHigh = MathMax(p0,p1);

            if(!(high15 >= zLow && low15 <= zHigh)) continue;

            lastTouchDirection  = -1;
            lastAdverseZoneName = nm;
            Print("*** BEARISH FVG TOUCHED in uptrend - longs suppressed: ", nm);
            break;
         }
      }

      // Check bearish 1H OBs
      if(lastTouchDirection != -1)
      {
         for(int k = 0; k < ArraySize(totalOB1h); k++)
         {
            string nm = totalOB1h[k];
            if(ObjectFind(0,nm) < 0) continue;
            if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrRed) continue;

            double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
            double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
            double zLow  = MathMin(p0,p1);
            double zHigh = MathMax(p0,p1);

            if(!(high15 >= zLow && low15 <= zHigh)) continue;

            lastTouchDirection  = -1;
            lastAdverseZoneName = nm;
            Print("*** BEARISH 1H OB TOUCHED in uptrend - longs suppressed: ", nm);
            break;
         }
      }
   }

   // -------- SCAN BULLISH ZONES FOR LONG ENTRY (only if not suppressed) --------
   if(!longZoneTouched && lastTouchDirection != -1)
   {
      Print("Checking for touch - bar1 high=", high15, " low=", low15);
      
      // ---- check all bullish OBs ----
      for(int i = 0; i < ArraySize(totalOB15m) && !longZoneTouched; i++)
      {
         string nm = totalOB15m[i];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrLime) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);
         if((zHigh - zLow) / _Point > 1000) { Print("OB too large - skipping"); continue; }

         if(UsePDFilter)
         {
            double pdEQ = GetPDEquilibrium();
            if(pdEQ > 0 && zHigh > pdEQ) { Print("Bullish OB not in discount - skipping"); continue; }
         }

         datetime obTime = obTimes15m[i];
         int obBar = iBarShift(_Symbol, PERIOD_M15, obTime, false);
         if(obBar - 1 < 3) { Print("OB too fresh - skipping"); continue; }

         if(!(high15 >= zLow && low15 <= zHigh)) continue;

         longZoneTouched = true;
         touchedObLow = zLow;
         touchedLongZoneName = nm;
         fvgExitConfirmedLong = true;
         longTouchBar = iBars(_Symbol, PERIOD_M15);
         waitingFor1mChochLong = true;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Long = 0.0;
         lastTouchDirection = +1;
         lastAdverseZoneName = nm;
         Print("*** 15M OB TOUCHED - waiting for 1M CHoCH");
      }

      // ---- check all bullish FVGs ----
      for(int j = 0; j < ArraySize(totalFVG15m) && !longZoneTouched; j++)
      {
         string nm = totalFVG15m[j];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrLime) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);
         if((zHigh - zLow) / _Point > 1000) { Print("FVG too large - skipping"); continue; }

         if(UsePDFilter)
         {
            double pdEQ = GetPDEquilibrium();
            if(pdEQ > 0 && zHigh > pdEQ) { Print("Bullish FVG not in discount - skipping"); continue; }
         }

         datetime fvgTime = barTimes15m[j];
         int fvgBar = iBarShift(_Symbol, PERIOD_M15, fvgTime, false);
         if(fvgBar - 1 < 3) { Print("FVG too fresh - skipping"); continue; }

         if(!(high15 >= zLow && low15 <= zHigh)) continue;

         longZoneTouched = true;
         touchedFvgLow = zLow;
         touchedLongZoneName = nm;
         fvgExitConfirmedLong = false;
         longTouchBar = iBars(_Symbol, PERIOD_M15);
         waitingFor1mChochLong = true;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Long = 0.0;
         lastTouchDirection = +1;
         lastAdverseZoneName = nm;
         Print("*** 15M FVG TOUCHED - waiting for 1M CHoCH");
      }

      // ---- check all bullish 1H OBs ----
      for(int k = 0; k < ArraySize(totalOB1h) && !longZoneTouched; k++)
      {
         string nm = totalOB1h[k];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrLime) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);
         if((zHigh - zLow) / _Point > 1000) { Print("1H OB too large - skipping"); continue; }

         if(UsePDFilter)
         {
            double pdEQ = GetPDEquilibrium();
            if(pdEQ > 0 && zHigh > pdEQ) { Print("Bullish 1H OB not in discount - skipping"); continue; }
         }

         datetime obTime = obTimes1h[k];
         int obBar = iBarShift(_Symbol, PERIOD_H1, obTime, false);
         if(obBar - 1 < 3) { Print("1H OB too fresh - skipping"); continue; }

         if(!(high15 >= zLow && low15 <= zHigh)) continue;

         longZoneTouched = true;
         touchedObLow = zLow;
         touchedLongZoneName = nm;
         fvgExitConfirmedLong = true;
         longTouchBar = iBars(_Symbol, PERIOD_M15);
         waitingFor1mChochLong = true;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Long = 0.0;
         lastTouchDirection = +1;
         lastAdverseZoneName = nm;
         Print("*** 1H OB TOUCHED - waiting for 1M CHoCH");
      }
   }
   
} // end longBias && isNewBar_5m

// -------- LONG 1M CHoCH --------
if(longBias && longZoneTouched && waitingFor1mChochLong && isNewBar_1m)
{
   if(touchedFvgLow > 0 && !fvgExitConfirmedLong)
   {
      double fh = MathMax(
         ObjectGetDouble(0, touchedLongZoneName, OBJPROP_PRICE, 0),
         ObjectGetDouble(0, touchedLongZoneName, OBJPROP_PRICE, 1)
      );
      if(iClose(_Symbol, PERIOD_M15, 1) > fh)
         fvgExitConfirmedLong = true;
   }
   if(touchedFvgLow > 0 && !fvgExitConfirmedLong) return;

   {
      const int len = Swing1mLength;
      int cb = len;
      bool isHigh = true, isLow = true;

      for(int i = 1; i <= len; i++)
      {
         if(iHigh(_Symbol,PERIOD_M1,cb) <= iHigh(_Symbol,PERIOD_M1,cb-i) ||
            iHigh(_Symbol,PERIOD_M1,cb) <  iHigh(_Symbol,PERIOD_M1,cb+i))
            isHigh = false;
         if(iLow(_Symbol,PERIOD_M1,cb)  >= iLow(_Symbol,PERIOD_M1,cb-i) ||
            iLow(_Symbol,PERIOD_M1,cb)  >  iLow(_Symbol,PERIOD_M1,cb+i))
            isLow = false;
      }
      if(isHigh) swingH_1m = iHigh(_Symbol, PERIOD_M1, cb);
      if(isLow)  swingL_1m = iLow (_Symbol, PERIOD_M1, cb);
   }

   if(swingL_1m <= 0)
   {
      for(int i = Swing1mLength + 1; i <= 100; i++)
      {
         bool isL = true;
         for(int j = 1; j <= Swing1mLength; j++)
         {
            if(iLow(_Symbol,PERIOD_M1,i) >= iLow(_Symbol,PERIOD_M1,i-j) ||
               iLow(_Symbol,PERIOD_M1,i) >  iLow(_Symbol,PERIOD_M1,i+j))
            { isL = false; break; }
         }
         if(isL) { swingL_1m = iLow(_Symbol,PERIOD_M1,i); break; }
      }
   }

   if(swingL_1m <= 0) return;

   double lastClose1m = iClose(_Symbol, PERIOD_M1, 1);

   if(lastClose1m <= swingL_1m) return;
   if(swingL_1m == lastProcessedSwingL_1m) return;

   chochSL_Long = swingL_1m - SLBufferPoints * _Point;
   lastProcessedSwingL_1m = swingL_1m;
   Print("*** 1M CHoCH UP confirmed at ", swingL_1m, " SL: ", chochSL_Long);

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sl    = chochSL_Long;
   double tp    = entry + 3.0 * (entry - sl);
   
   double lot = CalculateLotByRisk(entry, sl);
   if(lot <= 0) return;

   if(trade.Buy(lot,_Symbol,entry,sl,tp))
   {
      longZoneTouched = false;
      touchedObLow = 0;
      touchedFvgLow = 0;
      touchedLongZoneName = "";
      fvgExitConfirmedLong = false;
      longTouchBar = -1;
      waitingFor1mChochLong = false;
      swingH_1m = -1.0; swingL_1m = -1.0;
      lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
      chochSL_Long = 0.0;
      tradedToday = true;
   }
}
   
// ==================== SHORT BIAS BLOCK ====================
if(shortBias && isNewBar_5m)
{
   if(!IsValidTradingTime()) return;
   
   double high15 = iHigh(_Symbol, PERIOD_M15, 1);
   double low15  = iLow (_Symbol, PERIOD_M15, 1);

   // -------- INVALIDATION --------
   if(shortZoneTouched)
   {
      if(ObjectFind(0, touchedShortZoneName) < 0)
      {
         shortZoneTouched = false;
         touchedFvgHigh = 0;
         touchedObHigh = 0;
         touchedShortZoneName = "";
         fvgExitConfirmedShort = false;
         shortTouchBar = -1;
         waitingFor1mChochShort = false;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Short = 0.0;
         return;
      }
   }

   // -------- ADVERSE ZONE MITIGATION CHECK --------
   if(lastTouchDirection == +1 && lastAdverseZoneName != "")
   {
      if(ObjectFind(0, lastAdverseZoneName) < 0)
      {
         lastTouchDirection = 0;
         lastAdverseZoneName = "";
         Print("Adverse bullish zone mitigated - shorts re-enabled");
      }
   }

   // -------- SCAN FOR BULLISH ZONE TOUCH (suppress shorts) --------
   if(!shortZoneTouched && lastTouchDirection != +1)
   {
      // Check bullish 15M OBs
      for(int i = 0; i < ArraySize(totalOB15m); i++)
      {
         string nm = totalOB15m[i];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrLime) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);

         if(!(low15 <= zHigh && high15 >= zLow)) continue;

         lastTouchDirection  = +1;
         lastAdverseZoneName = nm;
         Print("*** BULLISH OB TOUCHED in downtrend - shorts suppressed: ", nm);
         break;
      }

      // Check bullish 15M FVGs
      if(lastTouchDirection != +1)
      {
         for(int j = 0; j < ArraySize(totalFVG15m); j++)
         {
            string nm = totalFVG15m[j];
            if(ObjectFind(0,nm) < 0) continue;
            if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrLime) continue;

            double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
            double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
            double zLow  = MathMin(p0,p1);
            double zHigh = MathMax(p0,p1);

            if(!(low15 <= zHigh && high15 >= zLow)) continue;

            lastTouchDirection  = +1;
            lastAdverseZoneName = nm;
            Print("*** BULLISH FVG TOUCHED in downtrend - shorts suppressed: ", nm);
            break;
         }
      }

      // Check bullish 1H OBs
      if(lastTouchDirection != +1)
      {
         for(int k = 0; k < ArraySize(totalOB1h); k++)
         {
            string nm = totalOB1h[k];
            if(ObjectFind(0,nm) < 0) continue;
            if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrLime) continue;

            double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
            double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
            double zLow  = MathMin(p0,p1);
            double zHigh = MathMax(p0,p1);

            if(!(low15 <= zHigh && high15 >= zLow)) continue;

            lastTouchDirection  = +1;
            lastAdverseZoneName = nm;
            Print("*** BULLISH 1H OB TOUCHED in downtrend - shorts suppressed: ", nm);
            break;
         }
      }
   }

   // -------- SCAN BEARISH ZONES FOR SHORT ENTRY (only if not suppressed) --------
   if(!shortZoneTouched && lastTouchDirection != +1)
   {
      Print("Checking for touch - bar1 high=", high15, " low=", low15);
      
      // ---- check all bearish OBs ----
      for(int i = 0; i < ArraySize(totalOB15m) && !shortZoneTouched; i++)
      {
         string nm = totalOB15m[i];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrRed) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);
         if((zHigh - zLow) / _Point > 1000) { Print("OB too large - skipping"); continue; }

         if(UsePDFilter)
         {
            double pdEQ = GetPDEquilibrium();
            if(pdEQ > 0 && zLow < pdEQ) { Print("Bearish OB not in premium - skipping"); continue; }
         }

         datetime obTime = obTimes15m[i];
         int obBar = iBarShift(_Symbol, PERIOD_M15, obTime, false);
         if(obBar - 1 < 3) { Print("OB too fresh - skipping"); continue; }

         if(!(low15 <= zHigh && high15 >= zLow)) continue;

         shortZoneTouched = true;
         touchedObHigh = zHigh;
         touchedShortZoneName = nm;
         fvgExitConfirmedShort = true;
         shortTouchBar = iBars(_Symbol, PERIOD_M15);
         waitingFor1mChochShort = true;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Short = 0.0;
         lastTouchDirection = -1;
         lastAdverseZoneName = nm;
         Print("*** 15M OB TOUCHED - waiting for 1M CHoCH");
      }

      // ---- check all bearish FVGs ----
      for(int j = 0; j < ArraySize(totalFVG15m) && !shortZoneTouched; j++)
      {
         string nm = totalFVG15m[j];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrRed) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);
         if((zHigh - zLow) / _Point > 1000) { Print("FVG too large - skipping"); continue; }

         if(UsePDFilter)
         {
            double pdEQ = GetPDEquilibrium();
            if(pdEQ > 0 && zLow < pdEQ) { Print("Bearish FVG not in premium - skipping"); continue; }
         }

         datetime fvgTime = barTimes15m[j];
         int fvgBar = iBarShift(_Symbol, PERIOD_M15, fvgTime, false);
         if(fvgBar - 1 < 3) { Print("FVG too fresh - skipping"); continue; }

         if(!(low15 <= zHigh && high15 >= zLow)) continue;

         shortZoneTouched = true;
         touchedFvgHigh = zHigh;
         touchedShortZoneName = nm;
         fvgExitConfirmedShort = false;
         shortTouchBar = iBars(_Symbol, PERIOD_M15);
         waitingFor1mChochShort = true;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Short = 0.0;
         lastTouchDirection = -1;
         lastAdverseZoneName = nm;
         Print("*** 15M FVG TOUCHED - waiting for 1M CHoCH");
      }

      // ---- check all bearish 1H OBs ----
      for(int k = 0; k < ArraySize(totalOB1h) && !shortZoneTouched; k++)
      {
         string nm = totalOB1h[k];
         if(ObjectFind(0,nm) < 0) continue;
         if((color)ObjectGetInteger(0,nm,OBJPROP_COLOR) != clrRed) continue;

         double p0 = ObjectGetDouble(0,nm,OBJPROP_PRICE,0);
         double p1 = ObjectGetDouble(0,nm,OBJPROP_PRICE,1);
         double zLow  = MathMin(p0,p1);
         double zHigh = MathMax(p0,p1);
         if((zHigh - zLow) / _Point > 1000) { Print("1H OB too large - skipping"); continue; }

         if(UsePDFilter)
         {
            double pdEQ = GetPDEquilibrium();
            if(pdEQ > 0 && zLow < pdEQ) { Print("Bearish 1H OB not in premium - skipping"); continue; }
         }

         datetime obTime = obTimes1h[k];
         int obBar = iBarShift(_Symbol, PERIOD_H1, obTime, false);
         if(obBar - 1 < 3) { Print("1H OB too fresh - skipping"); continue; }

         if(!(low15 <= zHigh && high15 >= zLow)) continue;

         shortZoneTouched = true;
         touchedObHigh = zHigh;
         touchedShortZoneName = nm;
         fvgExitConfirmedShort = true;
         shortTouchBar = iBars(_Symbol, PERIOD_M15);
         waitingFor1mChochShort = true;
         swingH_1m = -1.0; swingL_1m = -1.0;
         lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
         chochSL_Short = 0.0;
         lastTouchDirection = -1;
         lastAdverseZoneName = nm;
         Print("*** 1H OB TOUCHED - waiting for 1M CHoCH");
      }
   }
} // end shortBias && isNewBar_5m

// -------- SHORT 1M CHoCH --------
if(shortBias && shortZoneTouched && waitingFor1mChochShort && isNewBar_1m)
{
   if(touchedFvgHigh > 0 && !fvgExitConfirmedShort)
   {
      double fl = MathMin(
         ObjectGetDouble(0, touchedShortZoneName, OBJPROP_PRICE, 0),
         ObjectGetDouble(0, touchedShortZoneName, OBJPROP_PRICE, 1)
      );
      if(iClose(_Symbol, PERIOD_M15, 1) < fl)
         fvgExitConfirmedShort = true;
   }
   if(touchedFvgHigh > 0 && !fvgExitConfirmedShort) return;

   {
      const int len = Swing1mLength;
      int cb = len;
      bool isHigh = true, isLow = true;

      for(int i = 1; i <= len; i++)
      {
         if(iHigh(_Symbol,PERIOD_M1,cb) <= iHigh(_Symbol,PERIOD_M1,cb-i) ||
            iHigh(_Symbol,PERIOD_M1,cb) <  iHigh(_Symbol,PERIOD_M1,cb+i))
            isHigh = false;
         if(iLow(_Symbol,PERIOD_M1,cb)  >= iLow(_Symbol,PERIOD_M1,cb-i) ||
            iLow(_Symbol,PERIOD_M1,cb)  >  iLow(_Symbol,PERIOD_M1,cb+i))
            isLow = false;
      }
      if(isHigh) swingH_1m = iHigh(_Symbol, PERIOD_M1, cb);
      if(isLow)  swingL_1m = iLow (_Symbol, PERIOD_M1, cb);
   }

   if(swingH_1m <= 0)
   {
      for(int i = Swing1mLength + 1; i <= 100; i++)
      {
         bool isH = true;
         for(int j = 1; j <= Swing1mLength; j++)
         {
            if(iHigh(_Symbol,PERIOD_M1,i) <= iHigh(_Symbol,PERIOD_M1,i-j) ||
               iHigh(_Symbol,PERIOD_M1,i) <  iHigh(_Symbol,PERIOD_M1,i+j))
            { isH = false; break; }
         }
         if(isH) { swingH_1m = iHigh(_Symbol,PERIOD_M1,i); break; }
      }
   }

   if(swingH_1m <= 0) return;

   double lastClose1m = iClose(_Symbol, PERIOD_M1, 1);

   if(lastClose1m >= swingH_1m) return;
   if(swingH_1m == lastProcessedSwingH_1m) return;

   chochSL_Short = swingH_1m + SLBufferPoints * _Point;
   lastProcessedSwingH_1m = swingH_1m;
   Print("*** 1M CHoCH DOWN confirmed at ", swingH_1m, " SL: ", chochSL_Short);

   double entry = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double sl    = chochSL_Short;
   double tp    = entry - 3.0 * (sl - entry);

   double lot = CalculateLotByRisk(entry, sl);
   if(lot <= 0) return;

   if(trade.Sell(lot,_Symbol,entry,sl,tp))
   {
      shortZoneTouched = false;
      touchedObHigh = 0;
      touchedFvgHigh = 0;
      touchedShortZoneName = "";
      fvgExitConfirmedShort = false;
      shortTouchBar = -1;
      waitingFor1mChochShort = false;
      swingH_1m = -1.0; swingL_1m = -1.0;
      lastProcessedSwingH_1m = -1.0; lastProcessedSwingL_1m = -1.0;
      chochSL_Short = 0.0;
      tradedToday = true;
   }
}

} // end OnTick

void BOS(string objname, datetime time1, double price1, datetime time2, double price2, int direction, string text, color clr)
{
   ObjectCreate(0, objname, OBJ_ARROWED_LINE, 0, time1, price1, time2, price2);
   ObjectSetInteger(0, objname, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objname, OBJPROP_COLOR, clr);

   string Name = objname + "_" + text;
   ObjectCreate(0, Name, OBJ_TEXT, 0, time2, price2);
   ObjectSetInteger(0, Name, OBJPROP_FONTSIZE, 9);

   if(direction > 0)
   {
      ObjectSetString(0, Name, OBJPROP_TEXT, "  " + text);
      ObjectSetInteger(0, Name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   }
   else
   {
      ObjectSetString(0, Name, OBJPROP_TEXT, "  " + text);
      ObjectSetInteger(0, Name, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
   }
}

void SwingPoints(string objname, datetime time, double price, int arrCode, int direction, color clr)
{
   ObjectCreate(0, objname, OBJ_ARROW, 0, time, price);
   ObjectSetInteger(0, objname, OBJPROP_ARROWCODE, arrCode);
   ObjectSetInteger(0, objname, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, objname, OBJPROP_COLOR, clr);
   if(direction > 0)
      ObjectSetInteger(0, objname, OBJPROP_ANCHOR, ANCHOR_BOTTOM);
   else
      ObjectSetInteger(0, objname, OBJPROP_ANCHOR, ANCHOR_TOP);
}

void Rect(string objName, datetime time1, double price1, datetime time2, double price2, color clr)
{
   if(ObjectFind(0, objName) < 0)
   {
      ObjectCreate(0, objName, OBJ_RECTANGLE, 0, time1, price1, time2, price2);
   }
   ObjectSetInteger(0, objName, OBJPROP_TIME, 0, time1);
   ObjectSetDouble (0, objName, OBJPROP_PRICE,0, price1);
   ObjectSetInteger(0, objName, OBJPROP_TIME, 1, time2);
   ObjectSetDouble (0, objName, OBJPROP_PRICE,1, price2);
   ObjectSetInteger(0, objName, OBJPROP_FILL, true);
   ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, objName, OBJPROP_BACK, false);
   ObjectSetInteger(0, objName, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
}

void AsiaRangeBox(datetime sessionStart, datetime sessionEnd)
{
   if(asiahigh == 0.0 || asialow == 0.0) return;
   string RectName = "asia_range";
   if(ObjectFind(0, RectName) < 0)
      ObjectCreate(0, RectName, OBJ_RECTANGLE, 0, sessionStart, asiahigh, sessionEnd, asialow);
   ObjectSetInteger(0, RectName, OBJPROP_TIME,0, sessionStart);
   ObjectSetInteger(0, RectName, OBJPROP_TIME,1, sessionEnd);
   ObjectSetDouble (0, RectName, OBJPROP_PRICE,0, asiahigh);
   ObjectSetDouble (0, RectName, OBJPROP_PRICE,1, asialow);
   ObjectSetInteger(0, RectName, OBJPROP_COLOR, clrThistle);
   ObjectSetInteger(0, RectName, OBJPROP_FILL, true);
}

void DetectICT_OB(ENUM_TIMEFRAMES tf, string tfTag, int bosDir)
{
   int minImpulseBars = 1;
   int maxImpulseBars = 3;

   if(Bars(_Symbol, tf) < maxImpulseBars + ConsolidationBars + 5)
      return;

   for(int impulseLen = minImpulseBars; impulseLen <= maxImpulseBars; impulseLen++)
   {
      double impulseBody = 0.0;
      bool validImpulse = true;

      for(int j = 1; j <= impulseLen; j++)
      {
         double body = MathAbs(iClose(_Symbol,tf,j) - iOpen(_Symbol,tf,j));

         if(body <= 0) { validImpulse = false; break; }

         if(bosDir == 1 && iClose(_Symbol,tf,j) <= iOpen(_Symbol,tf,j)) { validImpulse = false; break; }
         if(bosDir == -1 && iClose(_Symbol,tf,j) >= iOpen(_Symbol,tf,j)) { validImpulse = false; break; }

         impulseBody += body;
      }

      if(!validImpulse) continue;

      int ob = impulseLen + 1;

      double prevBody = MathAbs(iClose(_Symbol,tf,ob+1) - iOpen(_Symbol,tf,ob+1));
      if(prevBody <= 0) continue;

      if(impulseBody < prevBody * ImpulseMultiplier) continue;

      double avgBody = 0.0;
      for(int k = ob + 1; k <= ob + ConsolidationBars; k++)
         avgBody += MathAbs(iClose(_Symbol,tf,k) - iOpen(_Symbol,tf,k));
      avgBody /= ConsolidationBars;

      if(impulseBody < avgBody * DisplacementMult) continue;

      double obBody = MathAbs(iClose(_Symbol,tf,ob) - iOpen(_Symbol,tf,ob));
      if(obBody <= 0) continue;
      if(obBody > impulseBody * MaxOBBodyRatio) continue;

      datetime obTime = iTime(_Symbol,tf,ob);
      string name = "ICT_OB_" + tfTag + "_" + TimeToString(obTime);
      
      if(ObjectFind(0,name) >= 0) return;
      
      datetime endTime = obTime + PeriodSeconds(tf) * OBExtendBars;
      
      double obHigh = iHigh(_Symbol, tf, ob);
      double obLow  = iLow (_Symbol, tf, ob);
      
      if(bosDir == -1) obHigh = MathMax(obHigh, iHigh(_Symbol, tf, 1));
      if(bosDir == 1)  obLow  = MathMin(obLow,  iLow (_Symbol, tf, 1));
      
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, obTime, obHigh, endTime, obLow);
      ObjectSetInteger(0, name, OBJPROP_FILL, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_COLOR, bosDir == 1 ? clrLime : clrRed);
                 
      if(tf == PERIOD_M15)
      {
         ArrayResize(totalOB15m, ArraySize(totalOB15m) + 1);
         totalOB15m[ArraySize(totalOB15m) - 1] = name;
         ArrayResize(obTimes15m, ArraySize(obTimes15m) + 1);
         obTimes15m[ArraySize(obTimes15m) - 1] = obTime;
      }
      else if(tf == PERIOD_H1)
      {
         ArrayResize(totalOB1h, ArraySize(totalOB1h) + 1);
         totalOB1h[ArraySize(totalOB1h) - 1] = name;
         ArrayResize(obTimes1h, ArraySize(obTimes1h) + 1);
         obTimes1h[ArraySize(obTimes1h) - 1] = obTime;
      }

      return;
   }
}

void CheckICTOBMitigation_M15()
{
   for(int j = ArraySize(totalOB15m) - 1; j >= 0; j--)
   {
      string objname = totalOB15m[j];
      bool mitigated = false;

      double p0 = ObjectGetDouble(0, objname, OBJPROP_PRICE, 0);
      double p1 = ObjectGetDouble(0, objname, OBJPROP_PRICE, 1);
      double obLow  = MathMin(p0, p1);
      double obHigh = MathMax(p0, p1);

      color obColor = (color)ObjectGetInteger(0, objname, OBJPROP_COLOR);
      datetime obTime = obTimes15m[j];

      int obBar = iBarShift(_Symbol, PERIOD_M15, obTime, false);
      if(obBar < 0) continue;

      int mitigationStartBar = obBar - 2;
      if(mitigationStartBar <= 1) continue;

      for(int k = mitigationStartBar; k >= 1; k--)
      {
         double barLow  = iLow (_Symbol, PERIOD_M15, k);
         double barHigh = iHigh(_Symbol, PERIOD_M15, k);

         if(obColor == clrLime)
         {
            if(barLow <= obLow) { mitigated = true; break; }
         }
         else if(obColor == clrRed)
         {
            if(barHigh >= obHigh) { mitigated = true; break; }
         }
      }

      if(mitigated)
      {
         ObjectDelete(0, objname);
         ArrayRemove(totalOB15m, j, 1);
         ArrayRemove(obTimes15m, j, 1);
      }
   }
}

void CheckICTOBMitigation_H1()
{
   for(int j = ArraySize(totalOB1h) - 1; j >= 0; j--)
   {
      string objname = totalOB1h[j];
      bool mitigated = false;

      double p0 = ObjectGetDouble(0, objname, OBJPROP_PRICE, 0);
      double p1 = ObjectGetDouble(0, objname, OBJPROP_PRICE, 1);
      double obLow  = MathMin(p0, p1);
      double obHigh = MathMax(p0, p1);

      color obColor = (color)ObjectGetInteger(0, objname, OBJPROP_COLOR);
      datetime obTime = obTimes1h[j];

      int obBar = iBarShift(_Symbol, PERIOD_H1, obTime, false);
      if(obBar < 0) continue;

      int mitigationStartBar = obBar - 2;
      if(mitigationStartBar <= 1) continue;

      for(int k = mitigationStartBar; k >= 1; k--)
      {
         double barLow  = iLow (_Symbol, PERIOD_H1, k);
         double barHigh = iHigh(_Symbol, PERIOD_H1, k);

         if(obColor == clrLime)
         {
            if(barLow <= obLow) { mitigated = true; break; }
         }
         else if(obColor == clrRed)
         {
            if(barHigh >= obHigh) { mitigated = true; break; }
         }
      }

      if(mitigated)
      {
         ObjectDelete(0, objname);
         ArrayRemove(totalOB1h, j, 1);
         ArrayRemove(obTimes1h, j, 1);
      }
   }
}

double CalculateLotByRisk(double entry, double sl)
{
   double riskMoney   = 50.0;
   double stopDollar  = MathAbs(entry - sl);
   if(stopDollar <= 0) return 0;

   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double lotRisk = contractSize * stopDollar;
   if(lotRisk <= 0) return 0;

   double lot = riskMoney / lotRisk;
   lot = NormalizeDouble(lot, 2);
   Print("Lot calc: stop=", stopDollar, " contractSize=", contractSize, " lotRisk=", lotRisk, " lot=", lot);
   return lot;
}

bool HasOpenPosition()
{
   return (PositionsTotal() > 0);
}

void DetectInducement()
{
   if(lastInducementTime > 0 && TimeCurrent() - lastInducementTime > PeriodSeconds(PERIOD_M15) * InducementValidBars)
   {
      inducementDetectedLong = false;
      inducementDetectedShort = false;
      lastInducementTime = 0;
   }

   if(ArraySize(swingLows_15m) < 2) return;
   if(ArraySize(swingHighs_15m) < 2) return;

   double recentSwingLow = swingLows_15m[ArraySize(swingLows_15m) - 1];
   double recentSwingHigh = swingHighs_15m[ArraySize(swingHighs_15m) - 1];

   for(int i = 2; i <= 5; i++)
   {
      double low_i = iLow(_Symbol, PERIOD_M15, i);
      double close_current = iClose(_Symbol, PERIOD_M15, 1);

      if(low_i < recentSwingLow && close_current > recentSwingLow)
      {
         if(!inducementDetectedLong)
         {
            inducementDetectedLong = true;
            lastInducementTime = TimeCurrent();
            Print("*** BULLISH INDUCEMENT - broke ", recentSwingLow, " ", i, " bars ago, now recovered");
            break;
         }
      }
   }

   for(int i = 2; i <= 5; i++)
   {
      double high_i = iHigh(_Symbol, PERIOD_M15, i);
      double close_current = iClose(_Symbol, PERIOD_M15, 1);

      if(high_i > recentSwingHigh && close_current < recentSwingHigh)
      {
         if(!inducementDetectedShort)
         {
            inducementDetectedShort = true;
            lastInducementTime = TimeCurrent();
            Print("*** BEARISH INDUCEMENT - broke ", recentSwingHigh, " ", i, " bars ago, now recovered");
            break;
         }
      }
   }
}

void ManagePartials()
{
   static ulong partialDoneTickets[];

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double entry   = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl      = PositionGetDouble(POSITION_SL);
      double tp      = PositionGetDouble(POSITION_TP);
      double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      long   posType = PositionGetInteger(POSITION_TYPE);
      double volume  = PositionGetDouble(POSITION_VOLUME);
      double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      if(tp <= 0 || sl <= 0) continue;

      double halfwayTarget;
      if(posType == POSITION_TYPE_BUY)
         halfwayTarget = entry + (tp - entry) * 0.5;
      else
         halfwayTarget = entry - (entry - tp) * 0.5;

      bool alreadyDone = false;
      for(int k = 0; k < ArraySize(partialDoneTickets); k++)
         if(partialDoneTickets[k] == ticket) { alreadyDone = true; break; }
      if(alreadyDone) continue;

      bool triggerLong  = (posType == POSITION_TYPE_BUY  && bid >= halfwayTarget);
      bool triggerShort = (posType == POSITION_TYPE_SELL && ask <= halfwayTarget);

      if(triggerLong || triggerShort)
      {
         double closeVol = NormalizeDouble(volume * 0.5, 2);
         closeVol = MathFloor(closeVol / lotStep) * lotStep;
         if(closeVol < minLot) closeVol = minLot;
         if(closeVol >= volume) continue;

         if(trade.PositionClosePartial(ticket, closeVol))
         {
            double newSL = NormalizeDouble(entry, _Digits);
            trade.PositionModify(ticket, newSL, tp);
            Print("Partial close: closed ", closeVol, " lots, SL moved to breakeven ", newSL);
            int n = ArraySize(partialDoneTickets);
            ArrayResize(partialDoneTickets, n + 1);
            partialDoneTickets[n] = ticket;
         }
         else
            Print("Partial close FAILED: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
   }
}

bool IsNewsTime()
{
   if(!UseNewsFilter) return false;

   datetime now = TimeCurrent();
   datetime from = now - NewsMinutesBefore * 60;
   datetime to   = now + NewsMinutesAfter  * 60;

   MqlCalendarValue values[];
   if(CalendarValueHistory(values, from, to) <= 0)
      return false;

   for(int i = 0; i < ArraySize(values); i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      if(event.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      string profit = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;

      if(country.currency == base || country.currency == profit)
      {
         Print("NEWS FILTER: Blocking trade - high impact news: ", event.name);
         return true;
      }
   }
   return false;
}

bool IsValidTradingTime()
{
   if(!UseSessionFilter) return true;

   if(IsNewsTime())
   {
      Print("REJECTED: High impact news window");
      return false;
   }
   
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int currentHour = dt.hour;
   
   bool isLondonSession = (currentHour >= LondonOpenHour && currentHour < LondonCloseHour);
   bool isNYSession = (currentHour >= NYOpenHour && currentHour < NYCloseHour);
   bool isAsianSession = (currentHour >= NYCloseHour || currentHour < LondonOpenHour);
   
   if(AvoidAsianSession && isAsianSession)
   {
      Print("REJECTED: Asian session (low liquidity)");
      return false;
   }
   
   if(isLondonSession || isNYSession)
   {
      Print("APPROVED: Trading during ", isLondonSession ? "London" : "NY", " session");
      return true;
   }
   
   Print("REJECTED: Outside London/NY sessions");
   return false;
}

void DrawPremiumDiscount()
{
   double rangeHigh = 0;
   double rangeLow  = 0;

   for(int i = 1; i <= 100 && rangeHigh == 0; i++)
   {
      double h = iHigh(_Symbol, PERIOD_H1, i);
      if(h == 0) continue;
      bool isPeak = true;
      for(int j = 1; j <= 3; j++)
      {
         if(h <= iHigh(_Symbol, PERIOD_H1, i+j) ||
            h <  iHigh(_Symbol, PERIOD_H1, i-j))
         { isPeak = false; break; }
      }
      if(isPeak) rangeHigh = h;
   }

   for(int i = 1; i <= 100 && rangeLow == 0; i++)
   {
      double l = iLow(_Symbol, PERIOD_H1, i);
      if(l == 0) continue;
      bool isTrough = true;
      for(int j = 1; j <= 3; j++)
      {
         if(l >= iLow(_Symbol, PERIOD_H1, i+j) ||
            l >  iLow(_Symbol, PERIOD_H1, i-j))
         { isTrough = false; break; }
      }
      if(isTrough) rangeLow = l;
   }

   if(rangeHigh == 0 || rangeLow == 0 || rangeHigh <= rangeLow) return;

   double equilibrium = (rangeHigh + rangeLow) / 2.0;

   datetime t1 = iTime(_Symbol, PERIOD_H1, 50);
   datetime t2 = iTime(_Symbol, PERIOD_H1, 0) + PeriodSeconds(PERIOD_H1) * 10;

   ObjectDelete(0, "PD_Premium");
   ObjectCreate(0, "PD_Premium", OBJ_TREND, 0, t1, rangeHigh, t2, rangeHigh);
   ObjectSetInteger(0, "PD_Premium", OBJPROP_COLOR,     clrRed);
   ObjectSetInteger(0, "PD_Premium", OBJPROP_STYLE,     STYLE_DASH);
   ObjectSetInteger(0, "PD_Premium", OBJPROP_WIDTH,     1);
   ObjectSetInteger(0, "PD_Premium", OBJPROP_RAY_RIGHT, false);

   ObjectDelete(0, "PD_Equilibrium");
   ObjectCreate(0, "PD_Equilibrium", OBJ_TREND, 0, t1, equilibrium, t2, equilibrium);
   ObjectSetInteger(0, "PD_Equilibrium", OBJPROP_COLOR,     clrYellow);
   ObjectSetInteger(0, "PD_Equilibrium", OBJPROP_STYLE,     STYLE_DASH);
   ObjectSetInteger(0, "PD_Equilibrium", OBJPROP_WIDTH,     1);
   ObjectSetInteger(0, "PD_Equilibrium", OBJPROP_RAY_RIGHT, false);

   ObjectDelete(0, "PD_Discount");
   ObjectCreate(0, "PD_Discount", OBJ_TREND, 0, t1, rangeLow, t2, rangeLow);
   ObjectSetInteger(0, "PD_Discount", OBJPROP_COLOR,     clrLime);
   ObjectSetInteger(0, "PD_Discount", OBJPROP_STYLE,     STYLE_DASH);
   ObjectSetInteger(0, "PD_Discount", OBJPROP_WIDTH,     1);
   ObjectSetInteger(0, "PD_Discount", OBJPROP_RAY_RIGHT, false);

   ObjectDelete(0, "PD_LabelPremium");
   ObjectCreate(0, "PD_LabelPremium", OBJ_TEXT, 0, t2, rangeHigh);
   ObjectSetString (0, "PD_LabelPremium", OBJPROP_TEXT,     "100% Premium");
   ObjectSetInteger(0, "PD_LabelPremium", OBJPROP_COLOR,    clrRed);
   ObjectSetInteger(0, "PD_LabelPremium", OBJPROP_FONTSIZE, 8);

   ObjectDelete(0, "PD_LabelEQ");
   ObjectCreate(0, "PD_LabelEQ", OBJ_TEXT, 0, t2, equilibrium);
   ObjectSetString (0, "PD_LabelEQ", OBJPROP_TEXT,     "50% EQ");
   ObjectSetInteger(0, "PD_LabelEQ", OBJPROP_COLOR,    clrYellow);
   ObjectSetInteger(0, "PD_LabelEQ", OBJPROP_FONTSIZE, 8);

   ObjectDelete(0, "PD_LabelDiscount");
   ObjectCreate(0, "PD_LabelDiscount", OBJ_TEXT, 0, t2, rangeLow);
   ObjectSetString (0, "PD_LabelDiscount", OBJPROP_TEXT,     "0% Discount");
   ObjectSetInteger(0, "PD_LabelDiscount", OBJPROP_COLOR,    clrLime);
   ObjectSetInteger(0, "PD_LabelDiscount", OBJPROP_FONTSIZE, 8);

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   inPremium  = (currentPrice > equilibrium);
   inDiscount = (currentPrice < equilibrium);
}
