#ifndef MOO_LLD_SHIM_H
#define MOO_LLD_SHIM_H

#ifdef __cplusplus
extern "C" {
#endif

// link native objects in-process through the lld library
int moo_lld_link(int argc, const char **arguments, char *error, int error_size);

#ifdef __cplusplus
}
#endif

#endif
