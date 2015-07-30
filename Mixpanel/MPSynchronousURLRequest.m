//
//  MPSynchronousURLRequest.m
//  Hotspot Shield
//
//  Created by David Gatwood on 7/30/15.
//  Copyright © 2015 AnchorFree. All rights reserved.
//

#import "MPSynchronousURLRequest.h"
#import <Foundation/Foundation.h>

@interface MPSynchronousURLRequest ()
@property (strong, nonatomic) NSURLRequest *request;
@property (strong, nonatomic) NSHTTPURLResponse *response;
@property (strong, nonatomic) NSMutableData *data;
@property (strong, nonatomic) NSCondition *condition;
@property (strong, nonatomic) NSURLConnection *connection;
@property (strong, nonatomic) NSError *error;

@property (assign, nonatomic) BOOL hasSignalled;
@end

@implementation MPSynchronousURLRequest

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    if ([NSRunLoop currentRunLoop] == [NSRunLoop mainRunLoop]) {
        NSLog(@"Usage error: This method cannot be safely called from the main run loop!\n");
        assert(false);
    }
    
    MPSynchronousURLRequest *mpsync = [[MPSynchronousURLRequest alloc] initWithRequest:request];

    [mpsync.condition lock];
    
    [mpsync start];
    
    [mpsync.condition wait];
    
    if (response) {
        *response = mpsync.response;
    }
    
    if (error) {
        *error = mpsync.error;
    }
    
    [mpsync.condition unlock];

    return mpsync.data;
}

- (instancetype)initWithRequest:(NSURLRequest *)request
{
    self = [super init];
    if (self) {
        self.request = request;
        self.condition = [[NSCondition alloc] init];
    }
    return self;
}

- (void)start
{
    /* NSURLConnection callbacks happen on the same run loop/thread as the caller, and this
       thread will be blocked, so we can't start the NSURLConnection from here.
     */
    [self performSelectorOnMainThread:@selector(startOnMainRunLoop) withObject:nil waitUntilDone:YES];
}

- (void)startOnMainRunLoop
{
    self.connection = [NSURLConnection connectionWithRequest:self.request delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    self.response = (NSHTTPURLResponse *)response;
    
    if (self.response.statusCode != 200) {
        self.data = nil;
        
        if (!self.hasSignalled) {
            [self.condition lock];
            [self.condition signal];
            [self.condition unlock];
            self.hasSignalled = YES;
        }
        
        [connection cancel];

        return;
    }
    
    self.data = [NSMutableData dataWithCapacity:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self.data appendData:[data copy]];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    if (error) {
        self.data = nil;
        self.error = error;
    }
    
    if (!self.hasSignalled) {
        [self.condition lock];
        [self.condition signal];
        [self.condition unlock];
        self.hasSignalled = YES;
    }
    
    [connection cancel]; // Not strictly necessary, but doesn't hurt.
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self connection:connection didFailWithError:nil];
}

@end
