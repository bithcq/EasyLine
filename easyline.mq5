#property strict
#property indicator_chart_window
#property indicator_plots 0

// 功能说明：EasyLine 是 MT5 图表画线工具，提供 8 个横排按钮、近点 OHLC 吸附绘制和一键清除。
// 主要类/函数职责：BuildUI 负责按钮条刷新，OnChartEvent 负责按钮与绘图事件，GetPointByXY 负责原始点和吸附点计算。
// 关键依赖：MetaTrader 5 图表对象 API、鼠标事件 API、CopyRates 行情访问接口。

input bool DeleteDrawnLinesOnRemove = false;
input int  PanelX = 10;
input int  PanelY = 20;

enum ENUM_TOOL_TYPE
  {
   TOOL_NONE = 0,
   TOOL_HLINE,
   TOOL_VLINE,
   TOOL_TREND
  };

struct SnapPoint
  {
   bool     ok;
   datetime t;
   double   p;
   bool     named_level;
   string   level_label;
  };

string         g_prefix = "";
ENUM_TOOL_TYPE g_tool = TOOL_NONE;
color          g_color = clrRed;
bool           g_has_anchor = false;
datetime       g_anchor_time = 0;
double         g_anchor_price = 0.0;
int            g_line_counter = 0;
int            g_panel_x = 0;
int            g_panel_y = 0;
int            g_drag_start_mouse_x = 0;
int            g_drag_start_mouse_y = 0;
int            g_drag_origin_x = 0;
int            g_drag_origin_y = 0;
bool           g_prev_left_down = false;
bool           g_prev_right_down = false;
bool           g_drag_candidate = false;
bool           g_is_controls_dragging = false;
bool           g_ignore_next_chart_click = false;
int            g_ignore_chart_click_x = -1;
int            g_ignore_chart_click_y = -1;
bool           g_ignore_next_release_click = false;
int            g_ignore_release_x = -1;
int            g_ignore_release_y = -1;
bool           g_restore_context_menu_on_right_up = false;
bool           g_saved_context_menu = true;
bool           g_saved_mouse_move   = false;
bool           g_saved_mouse_scroll = true;
bool           g_saved_object_delete = false;
string         g_base_high_line = "";
string         g_base_low_line  = "";
string         g_manual_hline_names[];

#define BUTTON_SIZE            40
#define BUTTON_COUNT           8
#define CONTROL_WIDTH          (BUTTON_SIZE * BUTTON_COUNT)
#define CONTROL_HEIGHT         BUTTON_SIZE
#define DRAG_THRESHOLD         4
#define FRAME_UNSELECTED_WIDTH 1
#define FRAME_SELECTED_WIDTH   3
#define ICON_MARGIN            7
#define ICON_THICKNESS         2
#define ICON_MAX_SEGMENTS      32
#define SNAP_PIXEL_THRESHOLD   10
#define LINE_LABEL_FONT_SIZE   9

#define NAME_PREVIEW          (g_prefix + "PREVIEW")
#define NAME_MARKER           (g_prefix + "MARKER")
#define NAME_LEVEL_HINT       (g_prefix + "LEVEL_HINT")

#define BTN_CLEAR             (g_prefix + "BTN_CLEAR")
#define BTN_COLOR_RED         (g_prefix + "BTN_COLOR_RED")
#define BTN_COLOR_YELLOW      (g_prefix + "BTN_COLOR_YELLOW")
#define BTN_COLOR_GREEN       (g_prefix + "BTN_COLOR_GREEN")
#define BTN_COLOR_BLUE        (g_prefix + "BTN_COLOR_BLUE")

#define BTN_TOOL_HLINE        (g_prefix + "BTN_TOOL_HLINE")
#define BTN_TOOL_VLINE        (g_prefix + "BTN_TOOL_VLINE")
#define BTN_TOOL_TREND        (g_prefix + "BTN_TOOL_TREND")

string LineLabelObjectName(const string line_name)
  {
   return line_name + "_LABEL";
  }

bool IsLineLabelObject(const string name)
  {
   int label_suffix_pos = StringLen(name) - 6;
   if(label_suffix_pos < 0)
      return false;

   return (StringSubstr(name, label_suffix_pos) == "_LABEL");
  }

bool IsOurObject(const string name)
  {
   return (StringFind(name, g_prefix) == 0);
  }

int FlagsToMask(const string s)
  {
   return (int)StringToInteger(s);
  }

bool IsRightDown(const int mask)
  {
   return ((mask & 2) != 0);
  }

bool IsLeftDown(const int mask)
  {
   return ((mask & 1) != 0);
  }

void DeleteObjectIfExists(const string name)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
  }

void ResetHorizontalReferenceState()
  {
   g_base_high_line = "";
   g_base_low_line = "";
   ArrayResize(g_manual_hline_names, 0);
  }

int FindManualHLineIndex(const string line_name)
  {
   int count = ArraySize(g_manual_hline_names);
   for(int i = 0; i < count; i++)
     {
      if(g_manual_hline_names[i] == line_name)
         return i;
     }

   return -1;
  }

void RemoveManualHLineAt(const int index)
  {
   int count = ArraySize(g_manual_hline_names);
   if(index < 0 || index >= count)
      return;

   for(int i = index; i < count - 1; i++)
      g_manual_hline_names[i] = g_manual_hline_names[i + 1];

   ArrayResize(g_manual_hline_names, count - 1);
  }

void RemoveManualHLineFromHistory(const string line_name)
  {
   int index = FindManualHLineIndex(line_name);
   if(index >= 0)
      RemoveManualHLineAt(index);
  }

void AppendManualHLine(const string line_name)
  {
   if(FindManualHLineIndex(line_name) >= 0)
      return;

   int count = ArraySize(g_manual_hline_names);
   ArrayResize(g_manual_hline_names, count + 1);
   g_manual_hline_names[count] = line_name;
  }

void PruneManualHLineHistory()
  {
   for(int i = ArraySize(g_manual_hline_names) - 1; i >= 0; i--)
     {
      if(ObjectFind(0, g_manual_hline_names[i]) < 0)
         RemoveManualHLineAt(i);
     }
  }

bool GetHorizontalLinePrice(const string line_name, double &price)
  {
   if(ObjectFind(0, line_name) < 0)
      return false;

   price = ObjectGetDouble(0, line_name, OBJPROP_PRICE, 0);
   return true;
  }

bool GetRightLabelAnchorTime(datetime &anchor_time)
  {
   int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int sub_window = 0;
   double dummy_price = 0.0;
   datetime visible_time = 0;
   int anchor_x = (int)MathMax(0, chart_width - 12);
   if(ChartXYToTimePrice(0, anchor_x, 10, sub_window, visible_time, dummy_price) && sub_window == 0)
     {
      anchor_time = visible_time;
      return true;
     }

   anchor_time = iTime(_Symbol, _Period, 0);
   return (anchor_time > 0);
  }

void SetHorizontalLineLabel(const string line_name, const string label_text)
  {
   string label_name = LineLabelObjectName(line_name);
   if(label_text == "")
     {
      DeleteObjectIfExists(label_name);
      return;
     }

   if(ObjectFind(0, line_name) < 0)
     {
      DeleteObjectIfExists(label_name);
      return;
     }

   datetime anchor_time = 0;
   if(!GetRightLabelAnchorTime(anchor_time))
      return;

   double price = 0.0;
   if(!GetHorizontalLinePrice(line_name, price))
      return;

   if(ObjectFind(0, label_name) < 0)
      ObjectCreate(0, label_name, OBJ_TEXT, 0, anchor_time, price);
   else
      ObjectMove(0, label_name, 0, anchor_time, price);

   color line_color = (color)ObjectGetInteger(0, line_name, OBJPROP_COLOR);
   ObjectSetString(0, label_name, OBJPROP_TEXT, label_text);
   ObjectSetString(0, label_name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, label_name, OBJPROP_FONTSIZE, LINE_LABEL_FONT_SIZE);
   ObjectSetInteger(0, label_name, OBJPROP_COLOR, line_color);
   ObjectSetInteger(0, label_name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, label_name, OBJPROP_BACK, false);
   ObjectSetInteger(0, label_name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, label_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, label_name, OBJPROP_SELECTED, false);
   ObjectSetString(0, label_name, OBJPROP_TOOLTIP, "\n");
  }

void RefreshHorizontalLineLabel(const string line_name)
  {
   string label_name = LineLabelObjectName(line_name);
   if(ObjectFind(0, label_name) < 0)
      return;

   string label_text = ObjectGetString(0, label_name, OBJPROP_TEXT);
   SetHorizontalLineLabel(line_name, label_text);
  }

void RefreshAllHorizontalLineLabels()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(IsEasyLineHorizontalLine(name))
         RefreshHorizontalLineLabel(name);
     }
  }

bool HasActiveBaselinePair(double &price_high, double &price_low)
  {
   if(g_base_high_line == "" || g_base_low_line == "")
      return false;

   if(FindManualHLineIndex(g_base_high_line) < 0 || FindManualHLineIndex(g_base_low_line) < 0)
      return false;

   if(!GetHorizontalLinePrice(g_base_high_line, price_high) ||
      !GetHorizontalLinePrice(g_base_low_line, price_low))
      return false;

   return true;
  }

void RefreshBaselineHorizontalLabels()
  {
   PruneManualHLineHistory();

   int count = ArraySize(g_manual_hline_names);
   for(int i = 0; i < count; i++)
      SetHorizontalLineLabel(g_manual_hline_names[i], "");

   double price_high = 0.0;
   double price_low = 0.0;
   bool has_active_pair = HasActiveBaselinePair(price_high, price_low);

   if(!has_active_pair)
     {
      g_base_high_line = "";
      g_base_low_line = "";

      if(count < 2)
         return;

      string line_a = g_manual_hline_names[count - 2];
      string line_b = g_manual_hline_names[count - 1];
      if(!GetHorizontalLinePrice(line_a, price_high) || !GetHorizontalLinePrice(line_b, price_low))
         return;

      g_base_high_line = line_a;
      g_base_low_line = line_b;
     }

   if(!GetHorizontalLinePrice(g_base_high_line, price_high) ||
      !GetHorizontalLinePrice(g_base_low_line, price_low))
      return;

   if(price_high < price_low)
     {
      string swap_name = g_base_high_line;
      g_base_high_line = g_base_low_line;
      g_base_low_line = swap_name;
     }

   SetHorizontalLineLabel(g_base_high_line, "H");
   SetHorizontalLineLabel(g_base_low_line, "L");
  }

void ShowLevelHintAtXY(const string label_text, const int mouse_x, const int mouse_y)
  {
   if(label_text == "")
     {
      DeleteObjectIfExists(NAME_LEVEL_HINT);
      return;
     }

   CreateOrUpdateLabel(NAME_LEVEL_HINT,
                       label_text,
                       mouse_x + 12,
                       (int)MathMax(0, mouse_y - 18),
                       clrPurple,
                       10);
  }

void DeleteIconSeries(const string button_name, const string part, const int from_index)
  {
   for(int i = from_index; i < ICON_MAX_SEGMENTS; i++)
      DeleteObjectIfExists(IconObjectName(button_name, part + "_" + IntegerToString(i)));
  }

void ResetTrendAnchor()
  {
   g_has_anchor  = false;
   g_anchor_time = 0;
   g_anchor_price = 0.0;
  }

void ClearPreview()
  {
   DeleteObjectIfExists(NAME_PREVIEW);
   DeleteObjectIfExists(NAME_MARKER);
   DeleteObjectIfExists(NAME_LEVEL_HINT);
  }

bool IsDrawingModeActive()
  {
   return (g_tool != TOOL_NONE);
  }

string IconObjectName(const string button_name, const string part)
  {
   return button_name + "_ICON_" + part;
  }

bool IsIconObject(const string name)
  {
   return (StringFind(name, "_ICON_") > 0);
  }

bool IsUiButtonName(const string name)
  {
   return (name == BTN_CLEAR ||
           name == BTN_COLOR_RED ||
           name == BTN_COLOR_YELLOW ||
           name == BTN_COLOR_GREEN ||
           name == BTN_COLOR_BLUE ||
           name == BTN_TOOL_HLINE ||
           name == BTN_TOOL_VLINE ||
           name == BTN_TOOL_TREND);
  }

string NormalizeUiTargetName(const string name)
  {
   int pos = StringFind(name, "_ICON_");
   if(pos > 0)
      return StringSubstr(name, 0, pos);

   return name;
  }

void ClampPanelPosition(int &panel_x, int &panel_y)
  {
   int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   int max_x = (int)MathMax(0, chart_width - CONTROL_WIDTH);
   int max_y = (int)MathMax(0, chart_height - CONTROL_HEIGHT);

   panel_x = (int)MathMax(0, MathMin(panel_x, max_x));
   panel_y = (int)MathMax(0, MathMin(panel_y, max_y));
  }

bool IsPointInsideRect(const int x,
                       const int y,
                       const int left,
                       const int top,
                       const int width,
                       const int height)
  {
   return (x >= left && x < left + width && y >= top && y < top + height);
  }

int ButtonLeft(const int index)
  {
   return g_panel_x + BUTTON_SIZE * index;
  }

int ButtonTop()
  {
   return g_panel_y;
  }

void SyncChartContextMenu()
  {
   bool enable_context_menu = (!IsDrawingModeActive() && !g_restore_context_menu_on_right_up);
   ChartSetInteger(0, CHART_CONTEXT_MENU, (enable_context_menu ? g_saved_context_menu : false));
  }

bool IsPointInsideControls(const int x, const int y)
  {
   return IsPointInsideRect(x, y, g_panel_x, g_panel_y, CONTROL_WIDTH, CONTROL_HEIGHT);
  }

void CreateOrUpdateLabel(const string name,
                         const string text,
                         const int x,
                         const int y,
                         const color clr,
                         const int font_size = 9)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
  }

void CreateOrUpdateBox(const string name,
                       const int x,
                       const int y,
                       const int w,
                       const int h,
                       const color bg,
                       const color border_color,
                       const ENUM_LINE_STYLE border_style,
                       const int border_width,
                       const long z_order = 1)
  {
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR, border_color);
   ObjectSetInteger(0, name, OBJPROP_STYLE, border_style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, border_width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, z_order);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
  }

void CreateOrUpdateIconSegment(const string name,
                               const int x,
                               const int y,
                               const int w,
                               const int h,
                               const color clr)
  {
   CreateOrUpdateBox(name, x, y, w, h, clr, clr, STYLE_SOLID, 1, 0);
  }

void CreateLineIcon(const string button_name,
                    const string part,
                    const int x1,
                    const int y1,
                    const int x2,
                    const int y2,
                    const color clr)
  {
   int dx = x2 - x1;
   int dy = y2 - y1;
   int steps = (int)MathMax(MathAbs(dx), MathAbs(dy));
   if(steps < 1)
      steps = 1;
   if(steps >= ICON_MAX_SEGMENTS)
      steps = ICON_MAX_SEGMENTS - 1;

   for(int i = 0; i <= steps; i++)
     {
      int x = x1 + (int)MathRound((double)dx * i / steps) - ICON_THICKNESS / 2;
      int y = y1 + (int)MathRound((double)dy * i / steps) - ICON_THICKNESS / 2;
      CreateOrUpdateIconSegment(IconObjectName(button_name, part + "_" + IntegerToString(i)),
                                x,
                                y,
                                ICON_THICKNESS,
                                ICON_THICKNESS,
                                clr);
     }

   DeleteIconSeries(button_name, part, steps + 1);
  }

void CreateToolIconHLine(const string button_name, const int button_left, const int button_top)
  {
   int center_y = button_top + BUTTON_SIZE / 2 - ICON_THICKNESS / 2;
   CreateOrUpdateIconSegment(IconObjectName(button_name, "MAIN_0"),
                             button_left + ICON_MARGIN,
                             center_y,
                             BUTTON_SIZE - ICON_MARGIN * 2,
                             ICON_THICKNESS,
                             clrPurple);
   DeleteIconSeries(button_name, "MAIN", 1);
  }

void CreateToolIconVLine(const string button_name, const int button_left, const int button_top)
  {
   int center_x = button_left + BUTTON_SIZE / 2 - ICON_THICKNESS / 2;
   CreateOrUpdateIconSegment(IconObjectName(button_name, "MAIN_0"),
                             center_x,
                             button_top + ICON_MARGIN,
                             ICON_THICKNESS,
                             BUTTON_SIZE - ICON_MARGIN * 2,
                             clrPurple);
   DeleteIconSeries(button_name, "MAIN", 1);
  }

void CreateToolIconTrend(const string button_name, const int button_left, const int button_top)
  {
   CreateLineIcon(button_name,
                  "MAIN",
                  button_left + BUTTON_SIZE - ICON_MARGIN - 1,
                  button_top + ICON_MARGIN,
                  button_left + ICON_MARGIN,
                  button_top + BUTTON_SIZE - ICON_MARGIN - 1,
                  clrPurple);
  }

void CreateToolIconClear(const string button_name, const int button_left, const int button_top)
  {
   CreateLineIcon(button_name,
                  "A",
                  button_left + ICON_MARGIN,
                  button_top + ICON_MARGIN,
                  button_left + BUTTON_SIZE - ICON_MARGIN - 1,
                  button_top + BUTTON_SIZE - ICON_MARGIN - 1,
                  clrPurple);
   CreateLineIcon(button_name,
                  "B",
                  button_left + ICON_MARGIN,
                  button_top + BUTTON_SIZE - ICON_MARGIN - 1,
                  button_left + BUTTON_SIZE - ICON_MARGIN - 1,
                  button_top + ICON_MARGIN,
                  clrPurple);
  }

void RemoveIconObjects()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(IsOurObject(name) && IsIconObject(name))
         ObjectDelete(0, name);
     }
  }

void UpdateButtonStates()
  {
   CreateOrUpdateBox(BTN_COLOR_RED,
                     ButtonLeft(0),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrRed,
                     (g_color == clrRed ? clrWhite : clrSilver),
                     STYLE_SOLID,
                     (g_color == clrRed ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));
   CreateOrUpdateBox(BTN_COLOR_YELLOW,
                     ButtonLeft(1),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrYellow,
                     (g_color == clrYellow ? clrWhite : clrSilver),
                     STYLE_SOLID,
                     (g_color == clrYellow ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));
   CreateOrUpdateBox(BTN_COLOR_GREEN,
                     ButtonLeft(2),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrLime,
                     (g_color == clrLime ? clrWhite : clrSilver),
                     STYLE_SOLID,
                     (g_color == clrLime ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));
   CreateOrUpdateBox(BTN_COLOR_BLUE,
                     ButtonLeft(3),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrBlue,
                     (g_color == clrBlue ? clrWhite : clrSilver),
                     STYLE_SOLID,
                     (g_color == clrBlue ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));

   CreateOrUpdateBox(BTN_TOOL_HLINE,
                     ButtonLeft(4),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrNONE,
                     (g_tool == TOOL_HLINE ? clrWhite : clrSilver),
                     (g_tool == TOOL_HLINE ? STYLE_SOLID : STYLE_DASH),
                     (g_tool == TOOL_HLINE ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));
   CreateOrUpdateBox(BTN_TOOL_VLINE,
                     ButtonLeft(5),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrNONE,
                     (g_tool == TOOL_VLINE ? clrWhite : clrSilver),
                     (g_tool == TOOL_VLINE ? STYLE_SOLID : STYLE_DASH),
                     (g_tool == TOOL_VLINE ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));
   CreateOrUpdateBox(BTN_TOOL_TREND,
                     ButtonLeft(6),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrNONE,
                     (g_tool == TOOL_TREND ? clrWhite : clrSilver),
                     (g_tool == TOOL_TREND ? STYLE_SOLID : STYLE_DASH),
                     (g_tool == TOOL_TREND ? FRAME_SELECTED_WIDTH : FRAME_UNSELECTED_WIDTH));
   CreateOrUpdateBox(BTN_CLEAR,
                     ButtonLeft(7),
                     ButtonTop(),
                     BUTTON_SIZE,
                     BUTTON_SIZE,
                     clrNONE,
                     clrSilver,
                     STYLE_DASH,
                     FRAME_UNSELECTED_WIDTH);
  }

void StartControlsDragCandidate(const int mouse_x, const int mouse_y)
  {
   g_drag_candidate = true;
   g_drag_start_mouse_x = mouse_x;
   g_drag_start_mouse_y = mouse_y;
   g_drag_origin_x = g_panel_x;
   g_drag_origin_y = g_panel_y;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
  }

bool HasExceededDragThreshold(const int mouse_x, const int mouse_y)
  {
   return (MathAbs(mouse_x - g_drag_start_mouse_x) >= DRAG_THRESHOLD ||
           MathAbs(mouse_y - g_drag_start_mouse_y) >= DRAG_THRESHOLD);
  }

void StartControlsDrag()
  {
   g_is_controls_dragging = true;
   g_drag_candidate = false;
   g_ignore_next_release_click = true;
   g_ignore_release_x = g_drag_start_mouse_x;
   g_ignore_release_y = g_drag_start_mouse_y;
   ClearPreview();
   ChartRedraw(0);
  }

void DragControlsToMouse(const int mouse_x, const int mouse_y)
  {
   int next_x = g_drag_origin_x + (mouse_x - g_drag_start_mouse_x);
   int next_y = g_drag_origin_y + (mouse_y - g_drag_start_mouse_y);
   ClampPanelPosition(next_x, next_y);

   if(next_x == g_panel_x && next_y == g_panel_y)
      return;

   g_panel_x = next_x;
   g_panel_y = next_y;
   BuildUI();
  }

void StopControlsDrag()
  {
   g_is_controls_dragging = false;
   g_drag_candidate = false;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_saved_mouse_scroll);
  }

void BuildUI()
  {
   int button_top = ButtonTop();

   CreateToolIconHLine(BTN_TOOL_HLINE, ButtonLeft(4), button_top);
   CreateToolIconVLine(BTN_TOOL_VLINE, ButtonLeft(5), button_top);
   CreateToolIconTrend(BTN_TOOL_TREND, ButtonLeft(6), button_top);
   CreateToolIconClear(BTN_CLEAR, ButtonLeft(7), button_top);

   UpdateButtonStates();
   ChartRedraw(0);
  }

bool IsEasyLineDrawObject(const string name)
  {
   return (StringFind(name, "EasyLine_") == 0 && StringFind(name, "_DRAW_") > 0);
  }

bool IsEasyLineHorizontalLine(const string name)
  {
   if(ObjectFind(0, name) < 0 || !IsEasyLineDrawObject(name) || IsLineLabelObject(name))
      return false;

   return ((ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE) == OBJ_HLINE);
  }

bool GetNearestBarIndex(const datetime target, int &best_index)
  {
   int idx1 = iBarShift(_Symbol, _Period, target, false);
   if(idx1 < 0)
      return false;

   best_index = idx1;
   datetime t1 = iTime(_Symbol, _Period, idx1);
   long d1 = (long)MathAbs((long)(target - t1));

   int idx2 = idx1 - 1;
   if(idx2 >= 0)
     {
      datetime t2 = iTime(_Symbol, _Period, idx2);
      long d2 = (long)MathAbs((long)(target - t2));
      if(d2 < d1)
         best_index = idx2;
     }

   return true;
  }

bool GetCurrentBaselinePrices(double &high_price, double &low_price)
  {
   if(g_base_high_line == "" || g_base_low_line == "")
      return false;

   if(!GetHorizontalLinePrice(g_base_high_line, high_price) ||
      !GetHorizontalLinePrice(g_base_low_line, low_price))
      return false;

   if(high_price - low_price < (_Point * 0.1))
      return false;

   return true;
  }

bool GetRawPointByXY(const int x, const int y, SnapPoint &sp)
  {
   sp.ok = false;
   sp.named_level = false;
   sp.level_label = "";
   int sub_window = 0;
   datetime raw_time = 0;
   double raw_price = 0.0;

   if(!ChartXYToTimePrice(0, x, y, sub_window, raw_time, raw_price))
      return false;

   if(sub_window != 0)
      return false;

   sp.t = raw_time;
   sp.p = NormalizeDouble(raw_price, _Digits);
   sp.ok = true;
   return true;
  }

void ConsiderNamedHorizontalLevel(const int raw_y,
                                  const datetime raw_time,
                                  const double candidate_price,
                                  const string label_text,
                                  int &best_distance,
                                  SnapPoint &sp)
  {
   int point_x = 0;
   int point_y = 0;
   if(!ChartTimePriceToXY(0, 0, raw_time, candidate_price, point_x, point_y))
      return;

   int distance = MathAbs(point_y - raw_y);
   if(distance > SNAP_PIXEL_THRESHOLD || distance >= best_distance)
      return;

   best_distance = distance;
   sp.ok = true;
   sp.t = raw_time;
   sp.p = NormalizeDouble(candidate_price, _Digits);
   sp.named_level = true;
   sp.level_label = label_text;
  }

bool TrySnapToNamedHorizontalLevel(const int mouse_y,
                                   const datetime raw_time,
                                   SnapPoint &sp)
  {
   if(g_tool != TOOL_HLINE)
      return false;

   double high_price = 0.0;
   double low_price = 0.0;
   if(!GetCurrentBaselinePrices(high_price, low_price))
      return false;

   double distance = high_price - low_price;
   if(distance < (_Point * 0.1))
      return false;

   sp.ok = false;
   sp.named_level = false;
   sp.level_label = "";

   int best_distance = SNAP_PIXEL_THRESHOLD + 1;

   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price + distance * 0.382, "38.2", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price + distance * 0.500, "50", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price + distance * 0.618, "61.8", best_distance, sp);

   ConsiderNamedHorizontalLevel(mouse_y, raw_time, high_price + distance, "1M", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price - distance, "1M", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, high_price + distance * 2.0, "2M", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price - distance * 2.0, "2M", best_distance, sp);

   ConsiderNamedHorizontalLevel(mouse_y, raw_time, high_price + distance * 0.382, "138.2", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price - distance * 0.382, "138.2", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, high_price + distance * 0.618, "161.8", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price - distance * 0.618, "161.8", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, high_price + distance * 1.618, "261.8", best_distance, sp);
   ConsiderNamedHorizontalLevel(mouse_y, raw_time, low_price - distance * 1.618, "261.8", best_distance, sp);

   return sp.ok;
  }

bool TrySnapToNearbyOhlcPoint(const int mouse_x,
                              const int mouse_y,
                              const datetime raw_time,
                              SnapPoint &sp)
  {
   int best_index = -1;
   if(!GetNearestBarIndex(raw_time, best_index))
      return false;

   int bars_count = Bars(_Symbol, _Period);
   if(bars_count <= 0)
      return false;

   int candidate_indexes[3];
   candidate_indexes[0] = best_index - 1;
   candidate_indexes[1] = best_index;
   candidate_indexes[2] = best_index + 1;

   int snap_threshold_sq = SNAP_PIXEL_THRESHOLD * SNAP_PIXEL_THRESHOLD;
   int best_distance_sq = snap_threshold_sq + 1;
   bool found = false;

   for(int i = 0; i < 3; i++)
     {
      int index = candidate_indexes[i];
      if(index < 0 || index >= bars_count)
         continue;

      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, _Period, index, 1, rates) != 1)
         continue;

      datetime point_time = rates[0].time;
      double prices[4];
      prices[0] = rates[0].open;
      prices[1] = rates[0].high;
      prices[2] = rates[0].low;
      prices[3] = rates[0].close;

      for(int price_idx = 0; price_idx < 4; price_idx++)
        {
         int point_x = 0;
         int point_y = 0;
         if(!ChartTimePriceToXY(0, 0, point_time, prices[price_idx], point_x, point_y))
            continue;

         int dx = point_x - mouse_x;
         int dy = point_y - mouse_y;
         int distance_sq = dx * dx + dy * dy;
         if(distance_sq > snap_threshold_sq)
            continue;

         if(!found || distance_sq < best_distance_sq)
           {
            best_distance_sq = distance_sq;
            sp.t = point_time;
            sp.p = NormalizeDouble(prices[price_idx], _Digits);
            found = true;
           }
        }
     }

   sp.ok = found;
   sp.named_level = false;
   sp.level_label = "";
   return found;
  }

bool GetPointByXY(const int x, const int y, SnapPoint &sp)
  {
   if(!GetRawPointByXY(x, y, sp))
      return false;

   SnapPoint named_level_point;
   if(TrySnapToNamedHorizontalLevel(y, sp.t, named_level_point))
     {
      sp = named_level_point;
      return true;
     }

   SnapPoint snap_point;
   if(TrySnapToNearbyOhlcPoint(x, y, sp.t, snap_point))
     {
      sp = snap_point;
      return true;
     }

   return true;
  }

void ApplyCommonPreviewProps(const string name)
  {
   ObjectSetInteger(0, name, OBJPROP_COLOR, g_color);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
  }

void ApplyCommonFinalProps(const string name)
  {
   ObjectSetInteger(0, name, OBJPROP_COLOR, g_color);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, "\n");
  }

void ExitDrawingMode(const bool restore_on_right_up = false)
  {
   g_tool = TOOL_NONE;
   ResetTrendAnchor();
   ClearPreview();
   g_restore_context_menu_on_right_up = restore_on_right_up;
   SyncChartContextMenu();
   UpdateButtonStates();
   ChartRedraw(0);
  }

void ShowMarker(const datetime t, const double p)
  {
   if(ObjectFind(0, NAME_MARKER) < 0)
      ObjectCreate(0, NAME_MARKER, OBJ_TEXT, 0, t, p);
   else
      ObjectMove(0, NAME_MARKER, 0, t, p);

   ObjectSetString(0, NAME_MARKER, OBJPROP_TEXT, "+");
   ObjectSetString(0, NAME_MARKER, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, NAME_MARKER, OBJPROP_FONTSIZE, 12);
   ObjectSetInteger(0, NAME_MARKER, OBJPROP_COLOR, g_color);
   ObjectSetInteger(0, NAME_MARKER, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(0, NAME_MARKER, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, NAME_MARKER, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, NAME_MARKER, OBJPROP_SELECTED, false);
   ObjectSetString(0, NAME_MARKER, OBJPROP_TOOLTIP, "\n");
  }

void ShowPreviewHLine(const double p)
  {
   if(ObjectFind(0, NAME_PREVIEW) < 0)
      ObjectCreate(0, NAME_PREVIEW, OBJ_HLINE, 0, 0, p);
   else
      ObjectMove(0, NAME_PREVIEW, 0, 0, p);

   ApplyCommonPreviewProps(NAME_PREVIEW);
  }

void ShowPreviewVLine(const datetime t)
  {
   if(ObjectFind(0, NAME_PREVIEW) < 0)
      ObjectCreate(0, NAME_PREVIEW, OBJ_VLINE, 0, t, 0);
   else
      ObjectMove(0, NAME_PREVIEW, 0, t, 0);

   ApplyCommonPreviewProps(NAME_PREVIEW);
   ObjectSetInteger(0, NAME_PREVIEW, OBJPROP_RAY, true);
  }

void ShowPreviewTrend(const datetime t1, const double p1, const datetime t2, const double p2)
  {
   if(ObjectFind(0, NAME_PREVIEW) < 0)
      ObjectCreate(0, NAME_PREVIEW, OBJ_TREND, 0, t1, p1, t2, p2);
   else
     {
      ObjectMove(0, NAME_PREVIEW, 0, t1, p1);
      ObjectMove(0, NAME_PREVIEW, 1, t2, p2);
     }

   ApplyCommonPreviewProps(NAME_PREVIEW);
   ObjectSetInteger(0, NAME_PREVIEW, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, NAME_PREVIEW, OBJPROP_RAY_RIGHT, false);
  }

void UpdatePreviewAtXY(const int x, const int y)
  {
   if(g_tool == TOOL_NONE)
     {
      ClearPreview();
      ChartRedraw(0);
      return;
     }

   SnapPoint sp;
   if(!GetPointByXY(x, y, sp))
     {
      ClearPreview();
      ChartRedraw(0);
      return;
     }

   ShowMarker(sp.t, sp.p);
   ShowLevelHintAtXY((sp.named_level ? sp.level_label : ""), x, y);

   if(g_tool == TOOL_HLINE)
      ShowPreviewHLine(sp.p);
   else if(g_tool == TOOL_VLINE)
      ShowPreviewVLine(sp.t);
   else if(g_tool == TOOL_TREND)
     {
      if(g_has_anchor)
         ShowPreviewTrend(g_anchor_time, g_anchor_price, sp.t, sp.p);
      else
         DeleteObjectIfExists(NAME_PREVIEW);
     }

   ChartRedraw(0);
  }

string NextLineName()
  {
   g_line_counter++;
   return g_prefix + "DRAW_" + IntegerToString(g_line_counter);
  }

void CreateFinalHLine(const double p,
                      const string line_label = "",
                      const bool affects_baseline = true)
  {
   string name = NextLineName();
   if(ObjectCreate(0, name, OBJ_HLINE, 0, 0, p))
     {
      ApplyCommonFinalProps(name);

      if(line_label != "")
         SetHorizontalLineLabel(name, line_label);

      if(affects_baseline)
        {
         AppendManualHLine(name);
         RefreshBaselineHorizontalLabels();
        }
     }
  }

void CreateFinalVLine(const datetime t)
  {
   string name = NextLineName();
   if(ObjectCreate(0, name, OBJ_VLINE, 0, t, 0))
     {
      ApplyCommonFinalProps(name);
      ObjectSetInteger(0, name, OBJPROP_RAY, true);
     }
  }

void CreateFinalTrend(const datetime t1, const double p1, const datetime t2, const double p2)
  {
   if(t1 == t2 && MathAbs(p1 - p2) < (_Point * 0.1))
      return;

   string name = NextLineName();
   if(ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
     {
      ApplyCommonFinalProps(name);
      ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
      ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
     }
  }

void HandleChartLeftClick(const int x, const int y)
  {
   if(g_tool == TOOL_NONE)
      return;

   SnapPoint sp;
   if(!GetPointByXY(x, y, sp))
      return;

   if(g_tool == TOOL_HLINE)
      CreateFinalHLine(sp.p, (sp.named_level ? sp.level_label : ""), !sp.named_level);
   else if(g_tool == TOOL_VLINE)
      CreateFinalVLine(sp.t);
   else if(g_tool == TOOL_TREND)
     {
      if(!g_has_anchor)
        {
         g_has_anchor = true;
         g_anchor_time = sp.t;
         g_anchor_price = sp.p;
        }
      else
        {
         CreateFinalTrend(g_anchor_time, g_anchor_price, sp.t, sp.p);
         g_anchor_time = sp.t;
         g_anchor_price = sp.p;
        }
     }

   UpdatePreviewAtXY(x, y);
  }

void SelectColor(const color c)
  {
   g_color = c;
   UpdateButtonStates();
   ChartRedraw(0);
  }

void SelectTool(const ENUM_TOOL_TYPE tool)
  {
   g_tool = tool;
   ResetTrendAnchor();
   ClearPreview();
   SyncChartContextMenu();
   UpdateButtonStates();
   ChartRedraw(0);
  }

void RemoveUiObjectsOnly()
  {
   DeleteObjectIfExists(BTN_CLEAR);
   DeleteObjectIfExists(BTN_COLOR_RED);
   DeleteObjectIfExists(BTN_COLOR_YELLOW);
   DeleteObjectIfExists(BTN_COLOR_GREEN);
   DeleteObjectIfExists(BTN_COLOR_BLUE);
   DeleteObjectIfExists(BTN_TOOL_HLINE);
   DeleteObjectIfExists(BTN_TOOL_VLINE);
   DeleteObjectIfExists(BTN_TOOL_TREND);
   RemoveIconObjects();
   DeleteObjectIfExists(NAME_PREVIEW);
   DeleteObjectIfExists(NAME_MARKER);
   DeleteObjectIfExists(NAME_LEVEL_HINT);
  }

void RemoveDrawnObjects()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix + "DRAW_") == 0)
         ObjectDelete(0, name);
     }
  }

void RemoveAllEasyLineDrawnObjects()
  {
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, 0, -1);
      if(IsEasyLineDrawObject(name))
         ObjectDelete(0, name);
     }

   g_line_counter = 0;
  }

void ClearAllDrawnLines()
  {
   RemoveAllEasyLineDrawnObjects();
   ResetHorizontalReferenceState();
   ResetTrendAnchor();
   ClearPreview();
   ChartRedraw(0);
  }

int OnInit()
  {
   g_prefix = "EasyLine_" + IntegerToString((int)ChartID()) + "_" + IntegerToString((int)TimeLocal()) + "_";

   g_saved_context_menu = (bool)ChartGetInteger(0, CHART_CONTEXT_MENU);
   g_saved_mouse_move   = (bool)ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE);
   g_saved_mouse_scroll = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
   g_saved_object_delete = (bool)ChartGetInteger(0, CHART_EVENT_OBJECT_DELETE);

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, true);

   g_color = clrRed;
   g_tool = TOOL_NONE;
   g_panel_x = PanelX;
   g_panel_y = PanelY;
   ClampPanelPosition(g_panel_x, g_panel_y);
   g_drag_start_mouse_x = 0;
   g_drag_start_mouse_y = 0;
   g_drag_origin_x = g_panel_x;
   g_drag_origin_y = g_panel_y;
   g_prev_left_down = false;
   g_prev_right_down = false;
   g_drag_candidate = false;
   g_is_controls_dragging = false;
   g_ignore_next_chart_click = false;
   g_ignore_chart_click_x = -1;
   g_ignore_chart_click_y = -1;
   g_ignore_next_release_click = false;
   g_ignore_release_x = -1;
   g_ignore_release_y = -1;
   g_restore_context_menu_on_right_up = false;
   ResetHorizontalReferenceState();
   ResetTrendAnchor();

   SyncChartContextMenu();
   BuildUI();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   ChartSetInteger(0, CHART_CONTEXT_MENU, g_saved_context_menu);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, g_saved_mouse_move);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_saved_mouse_scroll);
   ChartSetInteger(0, CHART_EVENT_OBJECT_DELETE, g_saved_object_delete);

   RemoveUiObjectsOnly();
   if(DeleteDrawnLinesOnRemove)
      RemoveDrawnObjects();

   ChartRedraw(0);
  }

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      ClampPanelPosition(g_panel_x, g_panel_y);
      BuildUI();
      RefreshBaselineHorizontalLabels();
      RefreshAllHorizontalLineLabels();
      return;
     }

   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      if(IsEasyLineHorizontalLine(sparam))
        {
         RefreshBaselineHorizontalLabels();
         RefreshAllHorizontalLineLabels();
         ChartRedraw(0);
        }

      return;
     }

   if(id == CHARTEVENT_OBJECT_DELETE)
     {
      if(IsEasyLineDrawObject(sparam) && !IsLineLabelObject(sparam))
        {
         DeleteObjectIfExists(LineLabelObjectName(sparam));
         RemoveManualHLineFromHistory(sparam);
         RefreshBaselineHorizontalLabels();
         ChartRedraw(0);
        }

      return;
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(g_ignore_next_release_click)
        {
         if(MathAbs((int)lparam - g_ignore_release_x) <= DRAG_THRESHOLD &&
            MathAbs((int)dparam - g_ignore_release_y) <= DRAG_THRESHOLD)
           {
            g_ignore_next_release_click = false;
            g_ignore_release_x = -1;
            g_ignore_release_y = -1;
            return;
           }

         g_ignore_next_release_click = false;
         g_ignore_release_x = -1;
         g_ignore_release_y = -1;
        }

      string target_name = NormalizeUiTargetName(sparam);

      if(IsOurObject(sparam) && IsUiButtonName(target_name))
        {
         g_ignore_next_chart_click = true;
         g_ignore_chart_click_x = (int)lparam;
         g_ignore_chart_click_y = (int)dparam;

         if(target_name == BTN_CLEAR)             ClearAllDrawnLines();
         else if(target_name == BTN_COLOR_RED)    SelectColor(clrRed);
         else if(target_name == BTN_COLOR_YELLOW) SelectColor(clrYellow);
         else if(target_name == BTN_COLOR_GREEN)  SelectColor(clrLime);
         else if(target_name == BTN_COLOR_BLUE)   SelectColor(clrBlue);
         else if(target_name == BTN_TOOL_HLINE)   SelectTool(TOOL_HLINE);
         else if(target_name == BTN_TOOL_VLINE)   SelectTool(TOOL_VLINE);
         else if(target_name == BTN_TOOL_TREND)   SelectTool(TOOL_TREND);

         return;
        }

      if(IsDrawingModeActive() && !IsPointInsideControls((int)lparam, (int)dparam))
        {
         g_ignore_next_chart_click = true;
         g_ignore_chart_click_x = (int)lparam;
         g_ignore_chart_click_y = (int)dparam;
         HandleChartLeftClick((int)lparam, (int)dparam);
        }

      return;
     }

   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      int mouse_x = (int)lparam;
      int mouse_y = (int)dparam;
      int mask = FlagsToMask(sparam);
      bool left_down = IsLeftDown(mask);
      bool right_down = IsRightDown(mask);

      if(g_restore_context_menu_on_right_up && !right_down && g_prev_right_down)
        {
         g_restore_context_menu_on_right_up = false;
         SyncChartContextMenu();
        }

      if(IsDrawingModeActive() && right_down && !g_prev_right_down)
        {
         ExitDrawingMode(true);
         g_prev_left_down = left_down;
         g_prev_right_down = right_down;
         return;
        }

      if(left_down && !g_prev_left_down && IsPointInsideControls(mouse_x, mouse_y))
         StartControlsDragCandidate(mouse_x, mouse_y);

      if(g_drag_candidate && left_down && !g_is_controls_dragging && HasExceededDragThreshold(mouse_x, mouse_y))
         StartControlsDrag();

      if(g_is_controls_dragging && left_down)
        {
         DragControlsToMouse(mouse_x, mouse_y);
         g_prev_left_down = left_down;
         g_prev_right_down = right_down;
         return;
        }

      if(!left_down && g_prev_left_down)
        {
         if(g_is_controls_dragging)
           {
            StopControlsDrag();
            g_ignore_release_x = mouse_x;
            g_ignore_release_y = mouse_y;
            g_prev_left_down = left_down;
            g_prev_right_down = right_down;
            return;
           }

         g_drag_candidate = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, g_saved_mouse_scroll);
        }

      if(IsPointInsideControls(mouse_x, mouse_y))
        {
         ClearPreview();
         ChartRedraw(0);
         g_prev_left_down = left_down;
         g_prev_right_down = right_down;
         return;
        }

      g_prev_left_down = left_down;
      g_prev_right_down = right_down;
      UpdatePreviewAtXY(mouse_x, mouse_y);
      return;
     }

   if(id == CHARTEVENT_CLICK)
     {
      if(g_ignore_next_release_click)
        {
         if(MathAbs((int)lparam - g_ignore_release_x) <= DRAG_THRESHOLD &&
            MathAbs((int)dparam - g_ignore_release_y) <= DRAG_THRESHOLD)
           {
            g_ignore_next_release_click = false;
            g_ignore_release_x = -1;
            g_ignore_release_y = -1;
            return;
           }

         g_ignore_next_release_click = false;
         g_ignore_release_x = -1;
         g_ignore_release_y = -1;
        }

      if(g_ignore_next_chart_click)
        {
         if(MathAbs((int)lparam - g_ignore_chart_click_x) <= DRAG_THRESHOLD &&
            MathAbs((int)dparam - g_ignore_chart_click_y) <= DRAG_THRESHOLD)
           {
            g_ignore_next_chart_click = false;
            g_ignore_chart_click_x = -1;
            g_ignore_chart_click_y = -1;
            return;
           }

         g_ignore_next_chart_click = false;
         g_ignore_chart_click_x = -1;
         g_ignore_chart_click_y = -1;
        }

      if(IsPointInsideControls((int)lparam, (int)dparam))
         return;

      HandleChartLeftClick((int)lparam, (int)dparam);
      return;
     }
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   return rates_total;
  }
