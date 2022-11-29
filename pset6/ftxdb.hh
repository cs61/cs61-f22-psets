#ifndef FTXDB_HH
#define FTXDB_HH
#include "io61.hh"
#include <mutex>
#include <random>
#include <stdexcept>
#include <utility>
struct ftx_acct;


// ftx_db
//    Structure representing an open account database.

struct ftx_db {
    io61_file* f;              // the file
    size_t naccounts;          // number of accounts in the file
    size_t asize = 16;         // size of an account record
    size_t balance_offset = 8; // offset of balance field within record
    size_t balance_size = 7;   // size of balance field within record
    static constexpr size_t max_asize = 512; // maximum asize allowed

    ftx_db(io61_file* f);
    ~ftx_db();
    static ftx_db* open_args(const io61_args& args);
};


// ftx_acct
//    Structure representing an account within an open `ftx_db`.

struct ftx_acct {
    const ftx_db& db;
    off_t offset;
    bool locked = false;

    inline ftx_acct(const ftx_db& db, size_t aindex);

    inline void lock();
    inline void unlock();
    inline int read(char* namebuf, size_t namesz, long* balance) const;
    inline int write(long balance) const;

    static int parse(
        const char* buf, size_t len, const ftx_db& db,
        char* namebuf, size_t namesz, long* balance
    );
    static std::pair<const char*, size_t> unparse(
        char* buf, size_t len, const ftx_db& db, long balance
    );
};


// Create an account object for account number `aindex`
inline ftx_acct::ftx_acct(const ftx_db& db_, size_t aindex)
    : db(db_) {
    assert(aindex < this->db.naccounts);
    this->offset = aindex * this->db.asize;
}


// Lock this account
inline void ftx_acct::lock() {
    assert(!this->locked);
    int r = io61_lock(this->db.f, this->offset, this->db.asize, LOCK_EX);
    assert(r == 0);
    this->locked = true;
}


// Unlock this account
inline void ftx_acct::unlock() {
    assert(this->locked);
    int r = io61_unlock(this->db.f, this->offset, this->db.asize);
    assert(r == 0);
    this->locked = false;
}


// Read this account’s current name and/or balance, storing the name
// in `namebuf[0..namesz-1]` and the balance in `*balance`
inline int ftx_acct::read(char* namebuf, size_t namesz, long* balance) const {
    // Read account from file; short reads are errors
    char buf[ftx_db::max_asize];
    ssize_t nr = io61_pread(this->db.f, buf, this->db.asize, this->offset);
    if (nr == 0 || nr == -1) {
        return nr;
    }

    // Parse account into name and/or balance components
    return parse(buf, nr, this->db, namebuf, namesz, balance);
}


// Write `balance` to the account database as this account’s new balance
inline int ftx_acct::write(long balance) const {
    // Stringify balance to stack buffer
    char buf[ftx_db::max_asize];
    auto [ptr, len] = unparse(buf, sizeof(buf), this->db, balance);
    if (len == 0) {
        return -1;
    }

    // Write unparsed balance to database file
    ssize_t nw = io61_pwrite(this->db.f, ptr, len,
                             this->offset + this->db.balance_offset);
    if (size_t(nw) != len) {
        errno = EINVAL;
        return -1;
    } else {
        return 0;
    }
}

#endif
