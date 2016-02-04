//
//  QNNTcpPing.m
//  NetDiag
//
//  Created by bailong on 16/1/26.
//  Copyright © 2016年 Qiniu Cloud Storage. All rights reserved.
//


#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <netdb.h>

#include <netinet/tcp.h>
#include <netinet/in.h>

#import "QNNTcpPing.h"

@interface QNNTcpPingResult()

-(instancetype)init:(NSInteger)code
                max:(NSTimeInterval)maxRtt
                min:(NSTimeInterval)minRtt
                avg:(NSTimeInterval)avgRtt
              count:(NSInteger)count;
@end

@implementation QNNTcpPingResult


-(NSString*) description{
    if (_code == 0) {
        return [NSString stringWithFormat:@"tcp connect min/avg/max = %f/%f/%fms", _minRtt, _avgRtt, _maxRtt];
    }
    return [NSString stringWithFormat:@"tcp connect failed %d", _code];
}

-(instancetype)init:(NSInteger)code
                max:(NSTimeInterval)maxRtt
                min:(NSTimeInterval)minRtt
                avg:(NSTimeInterval)avgRtt
              count:(NSInteger)count{
    if (self = [super init]) {
        _code = code;
        _minRtt = minRtt;
        _avgRtt = avgRtt;
        _count = count;
    }
    return self;
}

@end

@interface QNNTcpPing ()

@property (readonly) NSString* host;
@property (readonly) NSUInteger port;
@property (readonly) id<QNNOutputDelegate> output;
@property (readonly) QNNTcpPingCompleteHandler complete;
@property (readonly) NSInteger interval;
@property (readonly) NSInteger count;
@property (atomic) BOOL stopped;
@property NSUInteger index;
@end

@implementation QNNTcpPing

-(instancetype) init:(NSString*)host
                port:(NSInteger)port
              output:(id<QNNOutputDelegate>)output
            complete:(QNNTcpPingCompleteHandler)complete
               count:(NSInteger)count{
    if (self = [super init]) {
        _host = host;
        _port = port;
        _output = output;
        _complete = complete;
        _count = count;
        _stopped = NO;
    }
    return self;
}

-(void) run{
    [self.output write:[NSString stringWithFormat:@"connect to host %@ ...\n", _host]];
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_len = sizeof(addr);
    addr.sin_family = AF_INET;
    addr.sin_port = htons(_port);
    addr.sin_addr.s_addr = inet_addr([_host UTF8String]);
    if (addr.sin_addr.s_addr == INADDR_NONE) {
        struct hostent *host = gethostbyname([_host UTF8String]);
        if (host == NULL || host->h_addr == NULL) {
            [self.output write:@"Problem accessing the DNS"];
            if (_complete != nil) {
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                    _complete([self buildResult:-1006 durations:nil count:0]);
                });
            }
            return;
        }
        addr.sin_addr = *(struct in_addr *)host->h_addr;
        [self.output write:[NSString stringWithFormat:@"connect to ip %s ...\n", inet_ntoa(addr.sin_addr)]];
    }
    
    NSTimeInterval* intervals = (NSTimeInterval*)malloc(sizeof(NSTimeInterval)*_count);
    NSInteger index = 0;
    do {
        NSDate* t1 = [NSDate date];
        [self connect:&addr];
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:t1];
        intervals[_index] = duration;
        [self.output write:[NSString stringWithFormat:@"connected to ip %s, %f ms\n", inet_ntoa(addr.sin_addr), duration*1000]];
        if (index < _count) {
            [NSThread sleepForTimeInterval:0.1];
        }
    } while (++index < _count && !_stopped);
    if (_complete) {
        dispatch_async(dispatch_get_main_queue(), ^(void) {
            _complete([self buildResult:0 durations:intervals count:index]);
        });
    }
    free(intervals);
}

-(QNNTcpPingResult*)buildResult:(NSInteger)code
                      durations:(NSTimeInterval*)durations
                          count:(NSInteger)count{
    if (code < 0) {
        return [[QNNTcpPingResult alloc] init:code max:0 min:0 avg:0 count:1];
    }
    NSTimeInterval max = 0;
    NSTimeInterval min = 10000000;
    NSTimeInterval sum = 0;
    for (int i = 0; i<count; i++) {
        if (durations[i]>max) {
            max = durations[i];
        }
        if (durations[i]<min) {
            min = durations[i];
        }
        sum += durations[i];
    }
    NSTimeInterval avg = sum/count;
    return [[QNNTcpPingResult alloc]init:0 max:max min:min avg:avg count:count];
}

-(NSInteger) connect:(struct sockaddr_in*) addr{
    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock == -1) {
        return errno;
    }
    int on = 1;
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
    setsockopt(sock, IPPROTO_TCP, TCP_NODELAY, (char *) &on, sizeof(on));
    
    struct timeval timeout;
    timeout.tv_sec = 10;
    timeout.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout, sizeof(timeout));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout, sizeof(timeout));
    
    if (connect(sock, (struct sockaddr *)addr, sizeof(struct sockaddr)) < 0){
        int err =errno;
        close(sock);
        return err;
    }
    close(sock);
    return 0;
}


+(instancetype) start:(NSString*)host
               output:(id<QNNOutputDelegate>)output
             complete:(QNNTcpPingCompleteHandler)complete{
    return  [QNNTcpPing start:host port:80 output:output complete:complete count:3];
}

+(instancetype) start:(NSString*)host
                  port:(NSUInteger)port
               output:(id<QNNOutputDelegate>)output
             complete:(QNNTcpPingCompleteHandler)complete
                count:(NSInteger)count{
    QNNTcpPing* t = [[QNNTcpPing alloc] init:host
                                port:port
                              output:output
                            complete:complete
                               count:count];
    [t run];
    return t;
}

-(void)stop{
    _stopped = YES;
}

@end
