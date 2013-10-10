/*********************************************************************/
/*                          Litmus                                   */
/*                                                                   */
/*        Luc Maranget, INRIA Paris-Rocquencourt, France.            */
/*        Susmit Sarkar, University of Cambridge, UK.                */
/*                                                                   */
/*  Copyright 2010 Institut National de Recherche en Informatique et */
/*  en Automatique and the authors. All rights reserved.             */
/*  This file is distributed  under the terms of the Lesser GNU      */
/*  General Public License.                                          */
/*********************************************************************/

#ifndef _UTILS_H
#define _UTILS_H 1

#include <pthread.h>
/********/
/* Misc */
/********/

/* type of state for pseudorandom  generators */
typedef unsigned int st_t ;

void err(int e, char *msg) ;

void *malloc_check(size_t sz) ;

int max(int n,int m) ;

void pp_ints (FILE *fp,int *p,int n) ;

void *do_align(void *p, size_t sz) ;

void cat_file(char *path,char *msg,FILE *out) ;

/***********/
/* CPU set */
/***********/

typedef struct {
  int sz ;
  int *cpu ;
} cpus_t ;

cpus_t *cpus_create(int sz) ;
cpus_t *cpus_create_init(int sz, int t[]) ;
void cpus_free(cpus_t *p) ;
void cpus_dump(FILE *fp, cpus_t *p) ;
void cpus_dump_test(FILE *fp, int *p, int sz, cpus_t *cm,int nprocs) ;

int gcd(int a, int b) ;

cpus_t *coremap_seq(int navail, int nways) ;
cpus_t *coremap_end(int navail, int nways) ;

void custom_affinity
(st_t *st,cpus_t *cm,int **color,int *diff,cpus_t *aff_cpus,int n_exe, int *r) ;

/*************/
/* Int array */
/*************/

typedef struct {
  int sz ;
  int *t ;
} ints_t ;

void ints_dump(FILE *fp, ints_t *p) ;

/* Prefetch directives */
typedef enum {none, flush, touch, touch_store} prfdir_t ;

typedef struct {
  int nthreads,nvars ;
  char **names ;
  prfdir_t *t ;
} prfdirs_t ;

void prefetch_dump(FILE *fp, prfdirs_t *p) ;
int parse_prefetch(char *p, prfdirs_t *r) ;

/************************/
/* Command line options */
/************************/
typedef enum { aff_none, aff_incr, aff_random, aff_custom, } aff_mode_t ;

typedef struct {
  int verbose ;
  /* Test parmeters */
  int max_run ;
  int size_of_test ;
  int stride ;
  int avail ;
  int n_exe ;
  int sync_n ;
  /* Affinity */
  aff_mode_t aff_mode ;
  int aff_custom_enabled ;
  int aff_incr ;
  cpus_t *aff_cpus ;
  /* indirect mode */
  int shuffle ;
  /* loop test */
  int max_loop ;
  /* time base delays */
  ints_t * delta_tb ;
  /* prefetch control */
  prfdirs_t *prefetch ;
  int static_prefetch ;
  /* show time of synchronisation */
  int verbose_barrier ;
  /* Stop as soon as condition is settled */
  int speedcheck ;  
  /* Enforce fixed launch order (ie cancel change lauch) */
  int fix ;
  /* Dump prelude to test output */
  int prelude ;
} cmd_t ;

void parse_cmd(int argc, char **argv, cmd_t *def, cmd_t *p) ;


/********************/
/* Thread utilities */
/********************/

/* Mutex */

typedef pthread_mutex_t pm_t ;

pm_t *pm_create(void) ;
void pm_free(pm_t *p) ;
void pm_lock(pm_t *m) ;
void pm_unlock(pm_t *m) ;

/* Condition variable */

typedef struct {
  pm_t *c_mutex ;
  pthread_cond_t *c_cond ;
} pc_t ;

pc_t *pc_create(void) ;
void pc_free(pc_t *p) ;
void pc_wait(pc_t *p) ;
void pc_broadcast (pc_t *p) ;

/* Barrier */

/* Avoid pthread supplied barrier as they are not available in old versions */

typedef struct {
  volatile unsigned int count ;
  volatile int turn ;
  pc_t *cond ;
  unsigned int nprocs ; 
} pb_t ;


pb_t *pb_create(int nprocs) ;
void pb_free(pb_t *p) ;
void pb_wait(pb_t *p) ;


/* Or flag */

typedef struct {
  pc_t *cond ;
  int nprocs ;
  int count ;
  volatile int val ;
} po_t ;

po_t *po_create(int nprocs) ;
void po_free(po_t *p) ;
/* Initialize flag, must be called by all participant */
void po_reinit(po_t *p) ;
/* Return the 'or' of the v arguments of all participants */
int po_wait(po_t *p, int v) ;

/* One place buffer */

typedef struct {
  pc_t *cond ;
  int volatile some ;
  void * volatile val ;
} op_t ;

op_t *op_create(void) ;
void op_free(op_t *p) ;
void op_set(op_t *p, void *v) ;
void *op_get(op_t *p) ;

/* Thread launch and join */

typedef void* f_t(void *);

void launch(pthread_t *th, f_t *f, void *a) ;

void *join(pthread_t *th) ;

/* Thread cache */

typedef struct {
  int max_run ;
  op_t *op_arg,*op_ret ;
  void *arg ;
} sarg_t ;

f_t start_thread ;

/*****************/
/* Random things */
/*****************/

/* Unlocked random bit */

int rand_bit(st_t *st) ;
unsigned rand_k(st_t *st,unsigned n) ;

/* permutations */

void perm_prefix_ints(st_t *st,int t[], int used, int sz) ;
void perm_ints(st_t *st,int t[], int sz) ;
void perm_funs(st_t *st,f_t *t[], int sz) ;
void perm_threads(st_t *st,pthread_t t[], int sz) ;
void perm_ops(st_t *st,op_t *t[], int sz) ;

int check_shuffle(int **t, int *min, int sz) ;

/*********************/
/* Real time counter */
/*********************/

typedef unsigned long long tsc_t ;
#define PTSC "%llu"

/* Result in micro-seconds */
tsc_t timeofday(void) ;
double tsc_ratio(tsc_t t1, tsc_t t2) ;
double tsc_millions(tsc_t t) ;


#endif