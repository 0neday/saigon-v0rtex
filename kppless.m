//
//  kppless.m
//  Saigon
//
//  Created by xerub on 16/05/2017.
//  Copyright © 2017 xerub. All rights reserved.
//  Modified by Abraham Masri @cheesecakeufo on 10/18/17.

#include "unjail.h"
#include "offsets.h"
#include "libjb.h"
#include "jailbreak.h"
#include "Utilities.h"
#include "patchfinder64.h"
#include "kppless_inject.h"
#include "getshell.h"

// @qwertyoruiop's physalloc

static uint64_t
kalloc(vm_size_t size)
{
	mach_vm_address_t address = 0;
	mach_vm_allocate(tfp0, (mach_vm_address_t *)&address, size, VM_FLAGS_ANYWHERE);
	return address;
}

kern_return_t go_kppless(){
	
	
	/* 1. fix containermanagerd */
	
	
	/* 2. remount "/" */
	
	
	/* 3. untar bootstrap.tar */
	{
		char path[4096];
		uint32_t size = sizeof(path);
		_NSGetExecutablePath(path, &size);
		char *pt = realpath(path, NULL);
		
		NSString *execpath = [[NSString stringWithUTF8String:pt] stringByDeletingLastPathComponent];

		NSString *bootstrap = [execpath stringByAppendingPathComponent:@"bootstrap.tar"];
		FILE *a = fopen([bootstrap UTF8String], "rb");
		chdir("/tmp");
		untar(a, "bootstrap");
		fclose(a);
	}
	
	
	/* 4. inject trust cache */
	uint64_t trust_chain = find_trustcache();
	uint64_t amficache = find_amficache();
	printf("trust_chain = 0x%llx\n", trust_chain);
	
	struct trust_mem mem;
	mem.next = kread_uint64(trust_chain);
	*(uint64_t *)&mem.uuid[0] = 0xabadbabeabadbabe;
	*(uint64_t *)&mem.uuid[8] = 0xabadbabeabadbabe;
	
	int rv;
	rv = grab_hashes("/tmp/bins", kread, amficache, mem.next);
	printf("rv = %d, numhash = %d\n", rv, numhash);
	
	size_t length = (sizeof(mem) + numhash * 20 + 0xFFFF) & ~0xFFFF;
	uint64_t kernel_trust = kalloc(length);
	printf("alloced: 0x%zx => 0x%llx\n", length, kernel_trust);
	
	mem.count = numhash;
	kwrite(kernel_trust, &mem, sizeof(mem));
	kwrite(kernel_trust + sizeof(mem), allhash, numhash * 20);
	kwrite_uint64(trust_chain, kernel_trust);
	
	free(allhash);
	free(allkern);
	free(amfitab);
	
	/* 5. get shell */
	getshell();
	
	
	printf("done\n");
	
	return 0;
}
