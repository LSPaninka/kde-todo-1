/*
 * config.vapi — surfaces the compile-time constants defined in the
 * meson-generated config.h into the Ct namespace. Explicit cnames map to the
 * raw #define names (no CT_ namespace prefix).
 */
[CCode (cheader_filename = "config.h")]
namespace Ct {
    [CCode (cname = "APP_ID")]
    public const string APP_ID;
    [CCode (cname = "VERSION")]
    public const string VERSION;
    [CCode (cname = "GETTEXT_PACKAGE")]
    public const string GETTEXT_PACKAGE;
}
