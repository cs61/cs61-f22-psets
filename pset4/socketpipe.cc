#include <cstdio>
#include <cstring>
#include <cassert>
#include <cerrno>
#include <climits>
#include <vector>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

static int sockbuf = 0;

[[noreturn]] static void usage() {
    fprintf(stderr, "Usage: ./socketpipe CMD1 ARG... \"|\" CMD2 ARG...\n");
    exit(1);
}

static void make_child(int& last_sfdr, std::vector<const char*>& args,
                       bool last) {
    if (args.empty()) {
        usage();
    }
    args.push_back(nullptr);

    int sfdr = -1, sfdw = -1, r;
    if (!last) {
        int sfd = socket(AF_INET, SOCK_STREAM, 0);
        if (sfd < 0) {
            fprintf(stderr, "socketpair: %s\n", strerror(errno));
            exit(1);
        }

        sockaddr_in addr_in;
        addr_in.sin_family = AF_INET;
        addr_in.sin_port = 0;
        addr_in.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

        socklen_t addrlen = sizeof(addr_in);

        r = bind(sfd, (const sockaddr*) &addr_in, addrlen);
        assert(r == 0);

        r = listen(sfd, 2);
        assert(r == 0);

        addrlen = sizeof(addr_in);
        r = getsockname(sfd, (sockaddr*) &addr_in, &addrlen);
        assert(r == 0);
        assert(addrlen == sizeof(addr_in));
        assert(addr_in.sin_family == AF_INET);
        assert(addr_in.sin_port != 0);
        assert(addr_in.sin_addr.s_addr == htonl(INADDR_LOOPBACK));

        sfdr = socket(AF_INET, SOCK_STREAM, 0);
        assert(sfdr >= 0);
        r = connect(sfdr, (const sockaddr*) &addr_in, addrlen);
        assert(r == 0);

        sfdw = accept(sfd, nullptr, nullptr);
        assert(sfdw >= 0);

        r = shutdown(sfdr, SHUT_WR);
        assert(r == 0);
        r = shutdown(sfdw, SHUT_RD);
        assert(r == 0);
        r = close(sfd);
        assert(r == 0);

        #if 0
        r = socketpair(AF_UNIX, SOCK_STREAM, 0, sfd);
        shutdown(sfd[0], SHUT_WR);
        shutdown(sfd[1], SHUT_RD);
        #endif

        if (sockbuf != 0) {
            int optval = sockbuf;
            r = setsockopt(sfdw, SOL_SOCKET, SO_SNDBUF, &optval, sizeof(optval));
            assert(r == 0);
            optval = sockbuf;
            r = setsockopt(sfdr, SOL_SOCKET, SO_RCVBUF, &optval, sizeof(optval));
            assert(r == 0);
            timeval tv = { 0, 1000 };
            r = setsockopt(sfdw, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
            assert(r == 0);
            tv = { 0, 1000 };
            r = setsockopt(sfdr, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            assert(r == 0);
        }
    }

    pid_t p;
    if (last) {
        p = 0;
    } else {
        p = fork();
    }
    if (p == 0) {
        if (last_sfdr >= 0) {
            r = dup2(last_sfdr, STDIN_FILENO);
            assert(r == STDIN_FILENO);
            r = close(last_sfdr);
            assert(r == 0);
        }
        if (sfdw >= 0) {
            r = dup2(sfdw, STDOUT_FILENO);
            assert(r == STDOUT_FILENO);
            r = close(sfdw);
            assert(r == 0);
            r = close(sfdr);
            assert(r == 0);
        }
        r = execvp(args[0], (char* const*) args.data());
        fprintf(stderr, "%s: %s\n", args[0], strerror(errno));
        exit(1);
    } else if (p < 0) {
        fprintf(stderr, "fork: %s\n", strerror(errno));
        exit(1);
    }

    if (last_sfdr >= 0) {
        r = close(last_sfdr);
        assert(r == 0);
    }
    if (sfdw >= 0) {
        r = close(sfdw);
        assert(r == 0);
    }
    last_sfdr = sfdr;
}

int main(int argc, char* argv[]) {
    // parse `-B` option: socket buffer size
    if (argc > 1 && argv[1][0] == '-' && argv[1][1] == 'B') {
        const char* bufarg;
        if (argv[1][2] != '\0') {
            bufarg = argv[1] + 2;
            --argc;
            ++argv;
        } else {
            bufarg = argv[2];
            argc -= 2;
            argv += 2;
        }
        if (!bufarg) {
            usage();
        }
        char* endptr;
        unsigned long l = strtoul(bufarg, &endptr, 0);
        if (l > INT_MAX || endptr == bufarg || *endptr) {
            usage();
        }
        sockbuf = (int) l;
    }
    if (argc == 1) {
        usage();
    }

    std::vector<const char*> args;
    int last_sfdr = -1;
    for (int i = 1; i != argc; ++i) {
        if (strcmp(argv[i], "|") != 0) {
            args.push_back(argv[i]);
        } else {
            make_child(last_sfdr, args, false);
            args.clear();
        }
    }

    make_child(last_sfdr, args, true);
}
