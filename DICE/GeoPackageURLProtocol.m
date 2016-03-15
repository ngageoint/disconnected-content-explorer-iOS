//
//  GeoPackageURLProtocol.m
//  DICE
//
//  Created by Brian Osborn on 3/7/16.
//  Copyright © 2016 mil.nga. All rights reserved.
//

#import "GeoPackageURLProtocol.h"
#import "GPKGGeoPackageFactory.h"
#import "GPKGGeoPackageCache.h"
#import "GPKGIOUtils.h"
#import "GPKGGeoPackageValidate.h"
#import "GPKGGeoPackageTileRetriever.h"
#import "URLProtocolUtils.h"
#import "GPKGFeatureTiles.h"
#import "ReportUtils.h"
#import "DICEConstants.h"
#import "GeoPackageMapData.h"
#import "GPKGFeatureTileTableLinker.h"
#import "GPKGOverlayFactory.h"

@interface GeoPackageURLProtocol () <NSURLConnectionDelegate>

@property (nonatomic, strong) NSString * path;
@property (nonatomic, strong) NSArray<NSString *> * tables;
@property (nonatomic) int zoom;
@property (nonatomic) int x;
@property (nonatomic) int y;
@property (nonatomic, strong) NSURLConnection *connection;

@end

@implementation GeoPackageURLProtocol

static NSString *urlProtocolHandledKey = @"GeoPackageURLProtocolHandledKey";
static GPKGGeoPackageManager * manager;
static GPKGGeoPackageCache *cache;
static NSString *currentId;
static NSMutableDictionary<NSString *, GeoPackageMapData *> *mapData;

+ (void)start {
    manager = [GPKGGeoPackageFactory getManager];
    cache = [[GPKGGeoPackageCache alloc]initWithManager:manager];
    [NSURLProtocol registerClass:self];
}

+ (void) startCache: (NSString *) id{
    [self closeCache];
    currentId = id;
    mapData = [[NSMutableDictionary alloc] init];
}

+ (void) closeCache{
    [cache closeAll];
    if(currentId != nil){
        NSString * like = [NSString stringWithFormat:@"%@%@", DICE_TEMP_CACHE_PREFIX, @"%"];
        NSArray * geoPackages = [manager databasesLike:like];
        for(NSString * geoPackage in geoPackages){
            [manager delete:geoPackage andFile:NO];
        }
        currentId = nil;
    }
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    BOOL supports = NO;
    
    if(request != nil  && ![NSURLProtocol propertyForKey:urlProtocolHandledKey inRequest:request]){
        NSURL * url = [request URL];
        if(url != nil && [url isFileURL]){
            supports = [GPKGGeoPackageValidate hasGeoPackageExtension:url.path];
        }
    }
    
    return supports;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return [super requestIsCacheEquivalent:a toRequest:b];
}


- (id)initWithRequest:(NSURLRequest *)request cachedResponse:(NSCachedURLResponse *)cachedResponse client:(id <NSURLProtocolClient>)client {
    self = [super initWithRequest:request cachedResponse:cachedResponse client:client];
    if (self != nil) {
        NSURL * url = [request URL];
        
        self.path = url.path;
        
        NSDictionary<NSString *, NSArray *> * query = [URLProtocolUtils parseQueryFromUrl:url];
        self.tables = [query valueForKey:@"table"];
        self.zoom = [[[query valueForKey:@"z"] objectAtIndex:0] intValue];
        self.x = [[[query valueForKey:@"x"] objectAtIndex:0] intValue];
        self.y = [[[query valueForKey:@"y"] objectAtIndex:0] intValue];
    }
    return self;
}

- (void)startLoading {
    NSMutableURLRequest *newRequest = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:urlProtocolHandledKey inRequest:newRequest];
    
    self.connection = [NSURLConnection connectionWithRequest:newRequest delegate:self];
    
    NSString * nameWithExtension = [self.path lastPathComponent];
    NSString * name = [nameWithExtension stringByDeletingPathExtension];
    
    NSString * localPath = [GPKGIOUtils localDocumentsDirectoryPath:self.path];
    NSString * sharedPrefix = [NSString stringWithFormat:@"%@/%@", currentId, DICE_REPORT_SHARED_DIRECTORY];
    BOOL shared = [localPath hasPrefix:sharedPrefix];
    
    name = [GeoPackageURLProtocol reportIdPrefixWithName:name andReport:currentId andShare:shared];
    
    GPKGGeoPackage * geoPackage = nil;
    
    if(name != nil){
    
        if([manager exists:name]){
            @try {
                geoPackage = [cache getOrOpen:name];
            }
            @catch (NSException *exception) {
                [cache close:name];
                [manager delete:name andFile:NO];
                geoPackage = nil;
            }
        }
        
        if(geoPackage == nil){
            
            NSString * importPath = self.path;
            
            // If a shared file, check if the file exists in this report or another
            if(shared){
                NSFileManager * fileManager = [NSFileManager defaultManager];
                
                // If the file is not in this report, search other reports
                if(![fileManager fileExistsAtPath:importPath]){
                    
                    NSString * sharedSearchPath = [localPath substringFromIndex:[currentId length]];
                    
                    NSArray * reportDirectories = [ReportUtils getReportDirectories];
                    for(NSString * reportDirectory in reportDirectories){
                        
                        NSString * sharedLocation = [NSString stringWithFormat:@"%@%@", reportDirectory, sharedSearchPath];
                        
                        if([fileManager fileExistsAtPath:sharedLocation]){
                            importPath = sharedLocation;
                            break;
                        }
                    }

                }
            }
            
            [manager importGeoPackageAsLinkToPath:importPath withName:name];
            @try {
                geoPackage = [cache getOrOpen:name];
            }
            @catch (NSException *exception) {
                NSLog(@"Failed to open GeoPackage %@ at path: %@", name, importPath);
                geoPackage = nil;
            }
        }
    }
    
    NSData *tileData = nil;
    
    if(geoPackage != nil){
        for(NSString * table in self.tables){
            
            // Get or create the GeoPackage data
            GeoPackageMapData * geoPackageData = [mapData objectForKey:name];
            if(geoPackageData == nil){
                geoPackageData = [[GeoPackageMapData alloc] initWithName:name];
                [mapData setObject:geoPackageData forKey:name];
            }
            // Get or create the table data
            GeoPackageTableMapData * tableData = [geoPackageData getTable:table];
            if(tableData == nil){
                tableData = [[GeoPackageTableMapData alloc] initWithName:table];
                [geoPackageData addTable:tableData];
            }else{
                // Feature Overlay Queries have already been added for this table
                tableData = nil;
            }
            
            if([geoPackage isTileTable:table]){
            
                GPKGTileDao * tileDao = [geoPackage getTileDaoWithTableName:table];
                
                GPKGGeoPackageTileRetriever * retriever = [[GPKGGeoPackageTileRetriever alloc] initWithTileDao:tileDao];
                if([retriever hasTileWithX:self.x andY:self.y andZoom:self.zoom]){
                    GPKGGeoPackageTile * tile = [retriever getTileWithX:self.x andY:self.y andZoom:self.zoom];
                    if(tile != nil){
                        tileData = tile.data;
                    }
                }
                
                // If the first time handling this table
                if(tableData != nil){
                    // Check for linked feature tables
                    GPKGBoundedOverlay * geoPackageTileOverlay = [GPKGOverlayFactory getBoundedOverlay:tileDao];
                    GPKGFeatureTileTableLinker * linker = [[GPKGFeatureTileTableLinker alloc] initWithGeoPackage:geoPackage];
                    NSArray<GPKGFeatureDao *> * featureDaos = [linker getFeatureDaosForTileTable:tileDao.tableName];
                    for(GPKGFeatureDao * featureDao in featureDaos){
                        
                        // Create the feature tiles
                        GPKGFeatureTiles * featureTiles = [[GPKGFeatureTiles alloc] initWithFeatureDao:featureDao];
                        
                        // Create an index manager
                        GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
                        [featureTiles setIndexManager:indexer];
                        
                        // Add the feature overlay query
                        GPKGFeatureOverlayQuery * featureOverlayQuery = [[GPKGFeatureOverlayQuery alloc] initWithBoundedOverlay:geoPackageTileOverlay andFeatureTiles:featureTiles];
                        [tableData addFeatureOverlayQuery:featureOverlayQuery];
                    }
                }
                
            } else if([geoPackage isFeatureTable:table]){
                
                GPKGFeatureDao * featureDao = [geoPackage getFeatureDaoWithTableName:table];
                GPKGFeatureTiles * featureTiles = [[GPKGFeatureTiles alloc] initWithFeatureDao:featureDao];
                GPKGFeatureIndexManager * indexer = [[GPKGFeatureIndexManager alloc] initWithGeoPackage:geoPackage andFeatureDao:featureDao];
                [featureTiles setIndexManager:indexer];
                if([featureTiles isIndexQuery] && [featureTiles queryIndexedFeaturesCountWithX:self.x andY:self.y andZoom:self.zoom] > 0){
                    tileData = [featureTiles drawTileDataWithX:self.x andY:self.y andZoom:self.zoom];
                }
                
                if(tableData != nil && [featureTiles isIndexQuery]){
                    [featureTiles setIndexManager:indexer];

                    GPKGFeatureOverlay * featureOverlay = [[GPKGFeatureOverlay alloc] initWithFeatureTiles:featureTiles];
                    [featureOverlay setMinZoom:[NSNumber numberWithInt:[featureDao getZoomLevel]]];
                    
                    GPKGFeatureTileTableLinker * linker = [[GPKGFeatureTileTableLinker alloc] initWithGeoPackage:geoPackage];
                    NSArray<GPKGTileDao *> * tileDaos = [linker getTileDaosForFeatureTable:featureDao.tableName];
                    [featureOverlay ignoreTileDaos:tileDaos];
                    
                    GPKGFeatureOverlayQuery * featureOverlayQuery = [[GPKGFeatureOverlayQuery alloc] initWithFeatureOverlay:featureOverlay];
                    [tableData addFeatureOverlayQuery:featureOverlayQuery];
                }
            }
         
            if(tileData != nil){
                break;
            }
        }
    }
    
    NSURLResponse *response = [[NSURLResponse alloc] initWithURL:self.request.URL
                                                        MIMEType:nil
                                           expectedContentLength:tileData.length
                                                textEncodingName:nil];
    
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:tileData];
    [self.client URLProtocolDidFinishLoading:self];
    
}

- (void)stopLoading {
    [self.connection cancel];
    self.connection = nil;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.client URLProtocol:self didLoadData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    [self.client URLProtocolDidFinishLoading:self];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    [self.client URLProtocol:self didFailWithError:error];
}

+(NSString *) reportIdPrefixWithReport: (NSString *) report{
    NSString * reportIdPrefix = report;
    if(reportIdPrefix != nil){
        reportIdPrefix = [NSString stringWithFormat:@"%@%@-", DICE_TEMP_CACHE_PREFIX, reportIdPrefix];
    }
    return reportIdPrefix;
}

+(NSString *) reportIdPrefixWithName: (NSString *) name andReport: (NSString *) report andShare: (BOOL) share{
    NSString * reportId = name;
    if(!share){
        NSString * reportIdPrefix = [GeoPackageURLProtocol reportIdPrefixWithReport:report];
        if(reportIdPrefix != nil){
            reportId = [NSString stringWithFormat:@"%@%@", reportIdPrefix, reportId];
        }else{
            reportId = nil;
        }
    }
    return reportId;
}

+(NSString *) mapClickMessageWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds:(GPKGBoundingBox *)mapBounds{
    NSMutableString * clickMessage = [[NSMutableString alloc] init];
    for(GeoPackageMapData * geoPackageData in [mapData allValues]){
        NSString * message = [geoPackageData mapClickMessageWithLocationCoordinate:locationCoordinate andZoom:zoom andMapBounds:mapBounds];
        if(message != nil){
            if([clickMessage length] > 0){
                [clickMessage appendString:@"\n\n"];
            }
            [clickMessage appendString:message];
        }
    }
    return [clickMessage length] > 0 ? clickMessage : nil;
}

+(NSDictionary *) mapClickTableDataWithLocationCoordinate: (CLLocationCoordinate2D) locationCoordinate andZoom: (double) zoom andMapBounds:(GPKGBoundingBox *)mapBounds{
    NSMutableDictionary * clickData = [[NSMutableDictionary alloc] init];
    for(GeoPackageMapData * geoPackageData in [mapData allValues]){
        NSDictionary * geoPackageClickData = [geoPackageData mapClickTableDataWithLocationCoordinate:locationCoordinate andZoom:zoom andMapBounds:mapBounds];
        if(geoPackageClickData != nil){
            [clickData setObject:geoPackageClickData forKey:[geoPackageData getName]];
        }
    }
    return clickData.count > 0 ? clickData : nil;
}

@end
