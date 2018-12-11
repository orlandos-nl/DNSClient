#include <resolv.h>
#include "CResolvHelpers.h"

void initializeDNS() {
//    res_init();
}

struct sockaddr_in getHost() {
    return _res.nsaddr_list[0];
}
