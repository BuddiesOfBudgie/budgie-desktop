#ifndef __FUZZER_H__
#define __FUZZER_H__

#include <glib.h>

G_BEGIN_DECLS

gint fuzzer_get_fuzzy_score(const gchar *text, const gchar *pattern, gint max_distance);

G_END_DECLS

#endif
