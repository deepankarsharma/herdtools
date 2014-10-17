typedef struct {
  log_t key ;
  param_t p ;
  count_t c ;
  int ok ;
} entry_t ;

static void pp_entry(FILE *fp,entry_t *p, int verbose, char **group) {
  fprintf(fp,"%-6" PCTR "%c>",p->c,p->ok ? '*' : ':') ;
  pp_log(fp,&p->key) ;
  if (verbose) {
    fprintf(fp," # ") ;
    pp_param(fp,&p->p) ;
    if (group) fprintf(fp," %s",group[p->p.part]);
  }
  fprintf(fp,"\n") ;
}

typedef struct {
  int nhash ;
  entry_t t[HASHSZ] ;
} hash_t ;

static void pp_hash(FILE *fp,hash_t *t,int verbose,char **group) {
  for (int k = 0 ; k < HASHSZ ; k++) {
    entry_t *p = t->t+k ;
    if (p->c > 0) pp_entry(fp,p,verbose,group) ;
  }
}

#if 0
static void pp_hash_ok(FILE *fp,hash_t *t,char **group) {
  for (int k = 0 ; k < HASHSZ ; k++) {
    entry_t *p = t->t+k ;
    if (p->c > 0 && p->ok) pp_entry(fp,p,1,group) ;
  }
}
#endif


static void hash_init(hash_t *t) {
  t->nhash = 0 ;
  for (int k = 0 ; k < HASHSZ ; k++) t->t[k].c = 0 ;
}

/*
 Bob Jenkins hashword function, (Public domain)
 See <http://burtleburtle.net/bob/hash/doobs.html>
*/

#define rot(x,k) (((x)<<(k)) | ((x)>>(32-(k))))

#define mix(a,b,c) \
{ \
  a -= c;  a ^= rot(c, 4);  c += b; \
  b -= a;  b ^= rot(a, 6);  a += c; \
  c -= b;  c ^= rot(b, 8);  b += a; \
  a -= c;  a ^= rot(c,16);  c += b; \
  b -= a;  b ^= rot(a,19);  a += c; \
  c -= b;  c ^= rot(b, 4);  b += a; \
}

#define final(a,b,c) \
{ \
  c ^= b; c -= rot(b,14); \
  a ^= c; a -= rot(c,11); \
  b ^= a; b -= rot(a,25); \
  c ^= b; c -= rot(b,16); \
  a ^= c; a -= rot(c,4);  \
  b ^= a; b -= rot(a,14); \
  c ^= b; c -= rot(b,24); \
}

static uint32_t hashword(
const uint32_t *k,                   /* the key, an array of uint32_t values */
size_t          length)              /* the length of the key, in uint32_ts */
{
  uint32_t a,b,c;

  /* Set up the internal state */
  a = b = c = 0xdeadbeef ;

  /*------------------------------------------------- handle most of the key */
  while (length > 3)
  {
    a += k[0];
    b += k[1];
    c += k[2];
    mix(a,b,c);
    length -= 3;
    k += 3;
  }

  /*------------------------------------------- handle the last 3 uint32_t's */
  switch(length)                     /* all the case statements fall through */
  {
  case 3 : c+=k[2];
  case 2 : b+=k[1];
  case 1 : a+=k[0];
    final(a,b,c);
  case 0:     /* case 0: nothing left to add */
    break;
  }
  /*------------------------------------------------------ report the result */
  return c;
}

static uint32_t hash_log (log_t *key) {
  return hashword((uint32_t *)key,sizeof(log_t)/sizeof(uint32_t)) ;
}

static void hash_add(hash_t *t,log_t *key, param_t *v,count_t c,int ok) {
  uint32_t h = hash_log(key) ;
  h = h % HASHSZ ;
  for (int k = 0 ; k < HASHSZ ;  k++) {
    entry_t *p = t->t + h ;
    if (p->c == 0) { /* New entry */
      p->key = *key ;
      p->p = *v ;
      p->c = c ;
      p->ok = ok ;
      t->nhash++ ;
      return ;
    } else if (eq_log(key,&p->key)) {
      p->c += c ;
      return ;
    }
    h++ ;
    h %= HASHSZ ;
  }
  fprintf(stderr,"Hash table is full\n") ;
  exit(2) ;
}

static void hash_adds(hash_t *t, hash_t *f) {
  for (int k = 0 ; k < HASHSZ ; k++) {
    entry_t *p = f->t+k ;
    if (p->c > 0) {
      hash_add(t,&p->key,&p->p,p->c,p->ok) ;
    }
  }
}
