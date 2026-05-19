/* See LICENSE file for copyright and license details. */

/* appearance */
static const unsigned int borderpx  = 0;        /* border pixel of windows */
static const unsigned int snap      = 0;       /* snap pixel */
static const unsigned int systraypinning = 1;   /* 0: sloppy systray follows selected monitor, >0: pin systray to monitor X */
static const unsigned int systrayonleft = 0;    /* 0: systray in the right corner, >0: systray on left of status text */
static const unsigned int systrayspacing = 0;   /* systray spacing */
static const int systraypinningfailfirst = 0;   /* 1: if pinning fails, display systray on the first monitor, False: display s
     │ ystray on the last monitor*/
static const int showsystray        = 1;        /* 0 means no systray */
static const int vertpad            = 5;       /* vertical padding of bar */
static const int sidepad            = 5;       /* horizontal padding of bar */


static const unsigned int gappih    = 5;       /* horiz inner gap between windows */
static const unsigned int gappiv    = 5;       /* vert inner gap between windows */
static const unsigned int gappoh    = 5;       /* horiz outer gap between windows and screen edge */
static const unsigned int gappov    = 5;       /* vert outer gap between windows and screen edge */
static       int smartgaps          = 1;        /* 1 means no outer gap when there is only one window */
static const int showbar            = 1;        /* 0 means no bar */
static const int topbar             = 1;        /* 0 means bottom bar */
static const char statussep         = ';';      /* separator between status bars */

/*static const char *fonts[]          = { "Noto Sans Arabic:style=Regular:size=10" };*/
static const char font[]            = "monospace 10";
static const char dmenufont[]       = "Noto Sans Arabic:style=Regular:size=10 ";
/* dwm colors */
static char normbgcolor[]   = "#1e1e2e";
static char normbordercolor[] = "#313244";
static char normfgcolor[]   = "#cdd6f4";

static char selbgcolor[]    = "#89b4fa";
static char selbordercolor[] = "#89b4fa";
static char selfgcolor[]    = "#1e1e2e";

/* dwm colors */
static char termcol0[] = "#000000"; /* black   */
static char termcol1[] = "#ff0000"; /* red     */
static char termcol2[] = "#33ff00"; /* green   */
static char termcol3[] = "#ff0099"; /* yellow  */
static char termcol4[] = "#0066ff"; /* blue    */
static char termcol5[] = "#cc00ff"; /* magenta */
static char termcol6[] = "#00ffff"; /* cyan    */
static char termcol7[] = "#d0d0d0"; /* white   */
static char termcol8[]  = "#808080"; /* black   */
static char termcol9[]  = "#ff0000"; /* red     */
static char termcol10[] = "#33ff00"; /* green   */
static char termcol11[] = "#ff0099"; /* yellow  */
static char termcol12[] = "#0066ff"; /* blue    */
static char termcol13[] = "#cc00ff"; /* magenta */
static char termcol14[] = "#00ffff"; /* cyan    */
static char termcol15[] = "#ffffff"; /* white   */
/*static char *termcolor[] = {
  termcol0,
  termcol1,
  termcol2,
  termcol3,
  termcol4,
  termcol5,
  termcol6,
  termcol7,
  termcol8,
  termcol9,
  termcol10,
  termcol11,
  termcol12,
  termcol13,
  termcol14,
  termcol15,
};*/

/* terminal colors */
static char *colors[][3] = {
       /*               fg           bg           border   */
       [SchemeNorm] = { normfgcolor, normbgcolor, normbordercolor },
       [SchemeSel]  = { selfgcolor,  selbgcolor,  selbordercolor  },
};


/* tagging */
static const char *tags[] = { "1", "2", "3", "4", "5", "6", "7", "8", "9" };

static const Rule rules[] = {
	/* xprop(1):
	 *	WM_CLASS(STRING) = instance, class
	 *	WM_NAME(STRING) = title
	 */
	/* class      instance    title       tags mask     isfloating   monitor */
	{ "zen",  NULL,       NULL,       1 << 1,       0,           -1 },
	{ "dolphin",  NULL,       NULL,       1 << 2,       0,           -1 },
};

/* layout(s) */
static const float mfact     = 0.55; /* factor of master area size [0.05..0.95] */
static const int nmaster     = 1;    /* number of clients in master area */
static const int resizehints = 1;    /* 1 means respect size hints in tiled resizals */
static const int lockfullscreen = 1; /* 1 will force focus on the fullscreen window */
static const int refreshrate = 120;  /* refresh rate (per second) for client move/resize */

#define FORCE_VSPLIT 1  /* nrowgrid layout: force two clients to always split vertically */
#include "vanitygaps.c"
#include <X11/XF86keysym.h>

static const Layout layouts[] = {
	/* symbol     arrange function */
	{ "[]=",      tile },    /* first entry is default */
	{ "[M]",      monocle },
	{ "[@]",      spiral },
	{ "[\\]",     dwindle },
	{ "H[]",      deck },
	{ "TTT",      bstack },
	{ "===",      bstackhoriz },
	{ "HHH",      grid },
	{ "###",      nrowgrid },
	{ "---",      horizgrid },
	{ ":::",      gaplessgrid },
	{ "|M|",      centeredmaster },
	{ ">M>",      centeredfloatingmaster },
	{ "><>",      NULL },    /* no layout function means floating behavior */
	{ NULL,       NULL },
};

/* key definitions */
#define SUPERKEY Mod4Mask
#define ALTKEY Mod1Mask

#define TAGKEYS(KEY,TAG)                                                                                               \
       &((Keychord){1, {{SUPERKEY, KEY}},                                        view,           {.ui = 1 << TAG} }), \
       &((Keychord){1, {{SUPERKEY|ControlMask, KEY}},                            toggleview,     {.ui = 1 << TAG} }), \
       &((Keychord){1, {{SUPERKEY|ShiftMask, KEY}},                              tag,            {.ui = 1 << TAG} }), \
       &((Keychord){1, {{SUPERKEY|ControlMask|ShiftMask, KEY}},                  toggletag,      {.ui = 1 << TAG} }),

/* helper for spawning shell commands in the pre dwm-5.0 fashion */

#define SHCMD(cmd) { .v = (const char*[]){ "/usr/bin/bash", "-c", cmd, NULL } }

#define STATUSBAR "dwmblocks"

/* commands */
static char dmenumon[2] = "0"; /* component of dmenucmd, manipulated in spawn() */
static const char *dmenucmd[] = { "dmenu_run", "-fn", dmenufont, "-nb", normbgcolor, "-nf", normfgcolor, "-sb", selbordercolor, "-sf", selfgcolor, NULL };
static const char *termcmd[]  = { "alacritty", NULL };
static const char *github[] = { "nice", "-n", "10", "ionice", "-c2", "-n7", "chromium", "--app=https://github.com/mz2012007", NULL };
static const char *gpt[] = { "nice", "-n", "10", "ionice", "-c2", "-n7", "chromium", "--app=https://chat.openai.com", NULL };
static const char *google[] = { "nice", "-n", "10", "ionice", "-c2", "-n7", "chromium", "--app=https://google.com", NULL };
static const char *browser[] = { "nice", "-n", "10", "ionice", "-c2", "-n7", "zen", NULL };
static const char *runit_manager[] = { "/bin/sh", "-c", "~/scripts/window-script.sh ~/scripts/services/main.sh", NULL };


static const char *lang[] = { "kill -RTMIN+3 " ,"$(pidof dwmblocks)", NULL };

static const char *screenshot[] = {
  "/bin/sh",
  "-c",
  "flameshot full -p \"$HOME/Pictures/screenshots/$(date +%Y-%m-%d_%H-%M-%S).png\"",
  NULL
};

static const char *upvol[]   = { "bash", "-c", "pactl set-sink-volume @DEFAULT_SINK@ +5% && kill -RTMIN+1 $(pidof dwmblocks)", NULL };
static const char *downvol[]   = { "bash", "-c", "pactl set-sink-volume @DEFAULT_SINK@ -5% && kill -RTMIN+1 $(pidof dwmblocks)", NULL };
static const char *mutevol[] = { "bash", "-c", "pactl set-sink-mute @DEFAULT_SINK@ toggle && kill -RTMIN+1 $(pidof dwmblocks)", NULL };

static const char *lightup[]   = { "bash", "-c", "brightnessctl set +10%", NULL };
static const char *lightdown[] = { "bash", "-c", "brightnessctl set 10%-", NULL };

static const char *windows[] = {
  "rofi",
  "-show", "window",
  "-show-icons",
  "-theme", "/home/mz/.config/rofi/rofi.mz/themes/rounded-blue-dark.rasi",
  "-kb-row-right", "Alt+Tab",
  "-kb-row-left", "Alt+ISO_Left_Tab",
  "-kb-accept-entry", "!Alt-Tab,!Alt+ISO_Left_Tab,Return",
  "-kb-cancel", "Escape",
  NULL
};
static const char *rofi_menu[] = {
  "rofi",
  "-show", "drun",
  "-show-icons",
  "-theme", "/home/mz/.config/rofi/rofi.mz/themes/sidetab-nord.rasi",
  NULL
};

static const char *ncmpcpp_cmd[]       = { "~/scripts/window-script.sh", "/usr/bin/ncmpcpp", NULL };
static const char *mpc_toggle[]        = { "mpc", "toggle", NULL };
static const char *mpc_next[]          = { "mpc", "next", NULL };
static const char *mpc_prev[]          = { "mpc", "prev", NULL };
static const char *mpc_stop[]          = { "mpc", "stop", NULL };
static const char *mpc_repeat[]        = { "mpc", "repeat", NULL };
static const char *mpc_random[]        = { "mpc", "random", NULL };
static const char *mpc_seek0[]         = { "mpc", "seek", "0", NULL };
static const char *mpc_seek_plus10[]   = { "mpc", "seek", "+10", NULL };
static const char *mpc_seek_minus10[]  = { "mpc", "seek", "-10", NULL };
static const char *mpd_tracks[]        = { "bash", "-c", "$HOME/.config/mpd/scripts/mpd_tracks.sh", NULL };
static const char *mpd_playlists[]     = { "bash", "-c", "$HOME/.config/mpd/scripts/mpd_playlists.sh", NULL };


// autostrat //
static const char *const autostart[] = {
  "/home/mz/.config/dwm/dwm/autostart.sh", 
  //  "/home/mz/.config/dwm/statusbar.sh",
  NULL
};



static Keychord *keychords[] = {
        /*************************************** APPS ************************************************/
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_d}},                            spawn,          {.v = github } }),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_g}},                            spawn,          {.v = google } }),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_a}},                            spawn,          {.v = gpt } }),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_c}},                            spawn,          {.v = browser } }),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_s}},                            spawn,          {.v = runit_manager } }),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_e}},                            spawn,          SHCMD("nvim-qt")}),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_l}},                            spawn,          SHCMD("sudo lightdm-gtk-greeter-settings")}),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_p}},                            spawn,          SHCMD("dolphin")}),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_m}},                            spawn,          SHCMD("gnome-calculator")}),
       &((Keychord){2, {{SUPERKEY, XK_a}, {0, XK_f}},                            spawn,          SHCMD("flameshot gui")}),


       &((Keychord){1, {{0, XK_Print}},                                          spawn,          {.v = screenshot } }),
       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_d}},                             spawn,          {.v = dmenucmd } }),
       &((Keychord){1, {{SUPERKEY, XK_Return}},                                  spawn,          {.v = termcmd } }),
        /*********************************************************************************************/

        /*************************************** F ***************************************************/
       &((Keychord){1, {{0, XK_F1}},                                             spawn,          SHCMD("/home/mz/scripts/powermenu.sh") }),
    	 &((Keychord){1, {{0, XK_F5}},                                             xrdb,           {.v = NULL } }),
       &((Keychord){1, {{0, XK_F11}},                                            fullscreen,     {0} }),
       &((Keychord){1, {{0, XK_F12}},                                            spawn,          SHCMD("/home/mz/scripts/memreduct.sh") }),
        /*********************************************************************************************/

        /************************************** music ************************************************/
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_n}},      spawn, {.v = ncmpcpp_cmd}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_space}},  spawn, {.v = mpc_toggle}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_l}},      spawn, {.v = mpc_next}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_h}},      spawn, {.v = mpc_prev}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_s}},      spawn, {.v = mpc_stop}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_c}},      spawn, {.v = mpc_repeat}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_r}},      spawn, {.v = mpc_random}}),

       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_0}},      spawn, {.v = mpc_seek0}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_Right}},  spawn, {.v = mpc_seek_plus10}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_Left}},   spawn, {.v = mpc_seek_minus10}}),

       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_o}},      spawn, {.v = mpd_tracks}}),
       &((Keychord){2, {{SUPERKEY, XK_m}, {0, XK_p}},      spawn, {.v = mpd_playlists}}),
        /*********************************************************************************************/

        /**************************************** signals ********************************************/
       &((Keychord){1, {{ALTKEY|ShiftMask, 0}},                                spawn, { .v = lang } }),

         //             kill -RTMIN+10 $(pidof dwmblocks )

        /*********************************************************************************************/
        /**************************************** music&brightness ***********************************/
       &((Keychord){1, {{0, XF86XK_AudioRaiseVolume}},                           spawn, {.v = upvol } }),
       &((Keychord){1, {{0, XF86XK_AudioLowerVolume}},                           spawn, {.v = downvol }}),
       &((Keychord){1, {{0, XF86XK_AudioMute}},                                  spawn, {.v = mutevol }}),

       &((Keychord){1, {{0, XF86XK_MonBrightnessUp}},                            spawn, {.v = lightup }}),
       &((Keychord){1, {{0, XF86XK_MonBrightnessDown}},                          spawn, {.v = lightdown }}),
        /*********************************************************************************************/

       &((Keychord){1, {{ALTKEY, XK_Tab}},                                       spawn,          {.v = windows } }),
       &((Keychord){1, {{SUPERKEY, XK_d}},                                       spawn,          {.v = rofi_menu } }),
       
        /* toggle bar */
       &((Keychord){1, {{SUPERKEY, XK_b}},                                       togglebar,      {0} }),
        /* moving between windows */
       &((Keychord){1, {{SUPERKEY, XK_j}},                                       focusstack,     {.i = +1 } }),
       &((Keychord){1, {{SUPERKEY, XK_k}},                                       focusstack,     {.i = -1 } }),
        /* change num of masters */
       &((Keychord){1, {{SUPERKEY, XK_Right}},                                   incnmaster,     {.i = +1 } }),
       &((Keychord){1, {{SUPERKEY, XK_Left}},                                    incnmaster,     {.i = -1 } }),
        /* change area of masters to slaves */
       &((Keychord){1, {{SUPERKEY, XK_h}},                                       setmfact,       {.f = -0.05} }),
       &((Keychord){1, {{SUPERKEY, XK_l}},                                       setmfact,       {.f = +0.05} }),

        /* area of singl window */
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {SUPERKEY, XK_i}},             setcfact,       {.f = +0.25} }),
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {SUPERKEY, XK_d}},             setcfact,       {.f = -0.25} }),
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {SUPERKEY, XK_0}},             setcfact,       {.f =  0.00} }),       

       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_Return}},                        zoom,           {0} }),
       /* change between latest tags */
       &((Keychord){1, {{SUPERKEY, XK_Tab}},                                     view,           {0} }),
       /* kill app */
       &((Keychord){1, {{SUPERKEY, XK_q}},                                       killclient,     {0} }),
       &((Keychord){1, {{SUPERKEY|ControlMask, XK_c}},                           killclient,     {.ui = 1}} ),  // kill unselect
       &((Keychord){1, {{SUPERKEY|ShiftMask|ControlMask, XK_c}},                 killclient,     {.ui = 2}} ),  // killall
                                                                                                                  //
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_d}},                            setlayout,      {.v = &layouts[0]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_m}},                            setlayout,      {.v = &layouts[1]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_t}},                            setlayout,      {.v = &layouts[2]} }),
/*       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[3]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[4]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[5]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[6]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[7]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[8]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[9]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[10]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[11]} }),
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_ }},                            setlayout,      {.v = &layouts[12]} }), */
       &((Keychord){2, {{SUPERKEY, XK_w}, {0, XK_f}},                            setlayout,      {.v = &layouts[13]} }),

       &((Keychord){1, {{SUPERKEY, XK_space}},                                   setlayout,      {0} }),

       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_space}},                         togglefloating, {0} }),

        /******************************************* gaps ******************************************/
        /* all gaps */
       &((Keychord){2, {{SUPERKEY|ShiftMask|ControlMask, XK_g}, {0, XK_Right}},      incrgaps,    {.i = +1}}),
       &((Keychord){2, {{SUPERKEY|ShiftMask|ControlMask, XK_g}, {0, XK_Left}},      incrgaps,    {.i = -1}}),
        /* all inner gaps */
       &((Keychord){2, {{SUPERKEY|ShiftMask|ControlMask, XK_g}, {0, XK_k}},      incrigaps,   {.i = +1}}),
       &((Keychord){2, {{SUPERKEY|ShiftMask|ControlMask, XK_g}, {0, XK_j}},      incrigaps,   {.i = -1}}),
        /* all outer gaps */
       &((Keychord){2, {{SUPERKEY|ShiftMask|ControlMask, XK_g}, {0, XK_l}},      incrogaps,   {.i = +1}}),
       &((Keychord){2, {{SUPERKEY|ShiftMask|ControlMask, XK_g}, {0, XK_h}},      incrogaps,   {.i = -1}}),
        /* inner horizontal gaps */
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {0, XK_Right}},                  incrihgaps,  {.i = +1}}),
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {0, XK_Left}},                  incrihgaps,  {.i = -1}}),
        /* inner vertical gaps */
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {0, XK_Up}},                  incrivgaps,  {.i = +1}}),
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {0, XK_Down}},                  incrivgaps,  {.i = -1}}),
        /* outer horizontal gaps */
       &((Keychord){2, {{SUPERKEY, XK_g}, {0, XK_Right}},                            incrohgaps,  {.i = +1}}),
       &((Keychord){2, {{SUPERKEY, XK_g}, {0, XK_Left}},                            incrohgaps,  {.i = -1}}),
        /* outer vertical gaps */
       &((Keychord){2, {{SUPERKEY, XK_g}, {0, XK_Up}},                            incrovgaps,  {.i = +1}}),
       &((Keychord){2, {{SUPERKEY, XK_g}, {0, XK_Down}},                            incrovgaps,  {.i = -1}}),
        /* default on/off gaps */
       &((Keychord){2, {{SUPERKEY, XK_g}, {0, XK_0}},                            togglegaps,  {0}}),
       &((Keychord){2, {{SUPERKEY|ShiftMask, XK_g}, {0, XK_0}},                  defaultgaps, {0}}),
        /*********************************************************************************************/

       &((Keychord){1, {{SUPERKEY, XK_0}},                                       view,           {.ui = ~0 } }),
       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_0}},                             tag,            {.ui = ~0 } }),
       &((Keychord){1, {{SUPERKEY, XK_comma}},                                   focusmon,       {.i = -1 } }),
       &((Keychord){1, {{SUPERKEY, XK_period}},                                  focusmon,       {.i = +1 } }),
       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_comma}},                         tagmon,         {.i = -1 } }),
       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_period}},                        tagmon,         {.i = +1 } }),
       &((Keychord){1, {{SUPERKEY|ShiftMask, XK_q}},                             quit,           {0} }),
       &((Keychord){1, {{SUPERKEY, XK_s}},                                         togglesticky,   {0} }),

        /******************************************* tags ********************************************/
	   TAGKEYS(                        XK_1,                      0)
	   TAGKEYS(                        XK_2,                      1)
	   TAGKEYS(                        XK_3,                      2)
	   TAGKEYS(                        XK_4,                      3)
	   TAGKEYS(                        XK_5,                      4)
	   TAGKEYS(                        XK_6,                      5)
	   TAGKEYS(                        XK_7,                      6)
	   TAGKEYS(                        XK_8,                      7)
	   TAGKEYS(                        XK_9,                      8)
        /*********************************************************************************************/
};

/* button definitions */
/* click can be ClkTagBar, ClkLtSymbol, ClkStatusText, ClkWinTitle, ClkClientWin, or ClkRootWin */
static const Button buttons[] = {
	/* click                event mask      button          function        argument */
	{ ClkLtSymbol,          0,              Button1,        setlayout,      {0} },
	{ ClkLtSymbol,          0,              Button3,        setlayout,      {.v = &layouts[2]} },
	{ ClkWinTitle,          0,              Button2,        zoom,           {0} },

	{ ClkStatusText,        0,              Button1,        sigstatusbar,   {.i = 1} }, // left 
	{ ClkStatusText,        0,              Button2,        sigstatusbar,   {.i = 2} }, // middle
	{ ClkStatusText,        0,              Button3,        sigstatusbar,   {.i = 3} }, // right
  { ClkStatusText,        0,              Button4,        sigstatusbar,   {.i = 4} }, // scroll up
  { ClkStatusText,        0,              Button5,        sigstatusbar,   {.i = 5} }, // scroll down
  { ClkStatusText,        ShiftMask,      Button1,        sigstatusbar,   {.i = 6} }, // left

	{ ClkClientWin,         SUPERKEY,         Button1,        movemouse,      {0} },
	{ ClkClientWin,         SUPERKEY,         Button2,        togglefloating, {0} },
	{ ClkClientWin,         SUPERKEY,         Button3,        resizemouse,    {0} },
	{ ClkTagBar,            0,              Button1,        view,           {0} },
	{ ClkTagBar,            0,              Button3,        toggleview,     {0} },
	{ ClkTagBar,            SUPERKEY,         Button1,        tag,            {0} },
	{ ClkTagBar,            SUPERKEY,         Button3,        toggletag,      {0} },
};
