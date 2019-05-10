#include <resolv.h>
#include "CResolvHelpers.h"

struct sockaddr_in initializeDNS4() {
    struct __res_state *res;
    res = malloc(sizeof(struct __res_state));

    if(res_ninit(res) < 0) {
        return;
    }

    union res_sockaddr_union servers;
    res_getservers(res, &servers, 1);

    return servers.sin;
}

struct sockaddr_in6 initializeDNS6() {
    struct __res_state *res;
    res = malloc(sizeof(struct __res_state));

    if(res_ninit(res) < 0) {
        return;
    }

    union res_sockaddr_union servers;
    res_getservers(res, &servers, 1);

    return servers.sin6;
}
