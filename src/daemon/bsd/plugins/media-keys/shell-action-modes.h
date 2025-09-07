/**
 * ShellActionMode:
 * @SHELL_ACTION_MODE_NONE: block action
 * @SHELL_ACTION_MODE_NORMAL: allow action when in window mode,
 *     e.g. when the focus is in an application window
 * @SHELL_ACTION_MODE_OVERVIEW: allow action while the overview
 *     is active
 * @SHELL_ACTION_MODE_LOCK_SCREEN: allow action when the screen
 *     is locked, e.g. when the screen shield is shown
 * @SHELL_ACTION_MODE_UNLOCK_SCREEN: allow action in the unlock
 *     dialog
 * @SHELL_ACTION_MODE_LOGIN_SCREEN: allow action in the login screen
 * @SHELL_ACTION_MODE_SYSTEM_MODAL: allow action when a system modal
 *     dialog (e.g. authentification or session dialogs) is open
 * @SHELL_ACTION_MODE_LOOKING_GLASS: allow action in looking glass
 * @SHELL_ACTION_MODE_POPUP: allow action while a shell menu is open
 * @SHELL_ACTION_MODE_ALL: always allow action
 *
 * Controls in which GNOME Shell states an action (like keybindings and gestures)
 * should be handled.
*/
typedef enum {
  SHELL_ACTION_MODE_NONE          = 0,
  SHELL_ACTION_MODE_NORMAL        = 1 << 0,
  SHELL_ACTION_MODE_OVERVIEW      = 1 << 1,
  SHELL_ACTION_MODE_LOCK_SCREEN   = 1 << 2,
  SHELL_ACTION_MODE_UNLOCK_SCREEN = 1 << 3,
  SHELL_ACTION_MODE_LOGIN_SCREEN  = 1 << 4,
  SHELL_ACTION_MODE_SYSTEM_MODAL  = 1 << 5,
  SHELL_ACTION_MODE_LOOKING_GLASS = 1 << 6,
  SHELL_ACTION_MODE_POPUP         = 1 << 7,

  SHELL_ACTION_MODE_ALL = ~0,
} ShellActionMode;

/**
 * MetaKeyBindingFlags:
 * @META_KEY_BINDING_NONE: none
 * @META_KEY_BINDING_PER_WINDOW: per-window
 * @META_KEY_BINDING_BUILTIN: built-in
 * @META_KEY_BINDING_IS_REVERSED: is reversed
 * @META_KEY_BINDING_NON_MASKABLE: always active
 * @META_KEY_BINDING_IGNORE_AUTOREPEAT: ignore key autorepeat
 */
typedef enum
{
  META_KEY_BINDING_NONE,
  META_KEY_BINDING_PER_WINDOW   = 1 << 0,
  META_KEY_BINDING_BUILTIN      = 1 << 1,
  META_KEY_BINDING_IS_REVERSED  = 1 << 2,
  META_KEY_BINDING_NON_MASKABLE = 1 << 3,
  META_KEY_BINDING_IGNORE_AUTOREPEAT = 1 << 4,
} MetaKeyBindingFlags;