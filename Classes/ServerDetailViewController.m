//
//  ServerDetailViewController.m
//  RackspaceCloud
//
//  Created by Michael Mayo on 1/27/10.
//  Copyright Apple Inc 2010. All rights reserved.
//

// TODO: correct off-black in login screen background graphic

// TODO: ping server, open in safari, copy in clipboard, email IP address
// http://just-ping.com/index.php?vh=173.203.226.198&s=ping

#import "ServerDetailViewController.h"
#import "MasterViewController.h"
#import "ASICloudServersServer.h"
#import "ASICloudServersImage.h"
#import "ASICloudServersImageRequest.h"
#import "ASICloudServersFlavor.h"
#import "ASICloudServersFlavorRequest.h"
#import "AddServerViewController.h"
#import "RenameServerViewController.h"
#import "ResetServerAdminPasswordViewController.h"
#import "RebootServerViewController.h"
#import "ResizeServerViewController.h"
#import "CreateServerSnapshotViewController.h"
#import "ManageBackupSchedulesViewController.h"
#import "RebuildServerViewController.h"
#import "UIViewController+SpinnerView.h"
#import "ASICloudServersServerRequest.h"
#import "UIViewController+RackspaceCloud.h"

#import "ServersListViewController.h"


#define kNameSection 0
#define kDetailsSection 1
#define kPublicIPSection 2
#define kPrivateIPSection 3
#define kMetadataSection 4
#define kActionSection 5


@implementation ServerDetailViewController

@synthesize navigationBar, popoverController, detailItem;
@synthesize tableView;
@synthesize server;
@synthesize logoImageView, backgroundImageView;
@synthesize noServersView, noServersImage, noServersTitle, noServersMessage;
@synthesize serversListViewController;

// The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
    }
    return self;
}

-(id)initWithNoServersView {
    if ((self = [super initWithNibName:@"ServerDetailViewController" bundle:nil])) {
        // Custom initialization
		//self.view.hidden = YES;
		noServersView.hidden = NO;
		[self.view bringSubviewToFront:self.noServersView];
    }
    return self;
}

#pragma mark -
#pragma mark HTTP Response Handlers

-(void)loadServer {
	//[self request:[ASICloudServersServerRequest getServerRequest:self.server.serverId] behavior:@"retrieving your server" success:@selector(getServerSuccess:) showSpinner:NO];
	ASICloudServersServerRequest *request = [ASICloudServersServerRequest getServerRequest:self.server.serverId];
	[request setDelegate:self];
	[request setDidFinishSelector:@selector(getServerRequestFinished:)];
	[request setDidFailSelector:@selector(getServerRequestFailed:)];
	[request startAsynchronous];	
}

- (void)listBackupScheduleFinished:(ASICloudServersServerRequest *)request {
	NSLog(@"List Backup Response: %i - %@", [request responseStatusCode], [request responseString]);
	//[self hideSpinnerView];

    if (![request isSuccess]) {
        // TODO: try again up to three times?
        [self alertForCloudServersResponseStatusCode:[request responseStatusCode] behavior:@"retreiving all of your server details"];
    }	
}

-(void)deleteServerSuccess:(ASICloudServersServerRequest *)request {
    [self.serversListViewController loadServers];
}

-(void)deleteServerRequestFinished:(ASICloudServersServerRequest *)request {
	NSLog(@"Delete Response: %i - %@", [request responseStatusCode], [request responseString]);
	[self hideSpinnerView];
	
	if ([request responseStatusCode] == 202) {
		[self.serversListViewController loadServers:YES];		
	} else {
		[self alertForCloudServersResponseStatusCode:[request responseStatusCode] behavior:@"deleting your server"];
	}
}

-(void)deleteServerRequestFailed:(ASICloudServersServerRequest *)request {
	[self alertForCloudServersResponseStatusCode:[request responseStatusCode] behavior:@"deleting your server"];
}

-(void)getServerRequestFinished:(ASICloudServersServerRequest *)request {
	// TODO: tell jorge about weird bug where REBUILD progress starts at 100 and goes back to 0
	NSLog(@"Poll Server Response: %i - %@ Progress: %i", [request responseStatusCode], [request server].status, [request server].progress);
	if ([request isSuccess]) {
        self.server = [request server];
	}
    [self.tableView reloadData];
}

-(void)getServerRequestFailed:(ASICloudServersServerRequest *)request {
    NSLog(@"Poll Server Failed");
    [self.tableView reloadData]; // keep polling!
}

#pragma mark -
#pragma mark Progress Bar Animation

- (void)animateProgressBarTo:(float)to {
	if (progressTimer == nil) {
		progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(moveProgress) userInfo:nil repeats:YES];
	}
}

- (void)moveProgress {
	if (progressView.progress < [self.server humanizedProgress] * 0.01) {
		progressView.progress += 0.01;
	} else if (progressView.progress > [self.server humanizedProgress] * 0.01) {
		progressView.progress = [self.server humanizedProgress] * 0.01;
	} else if (progressView.progress == [self.server humanizedProgress] * 0.01) {
		[progressTimer invalidate];
		progressTimer = nil;
	}
}

#pragma mark -
#pragma mark Managing the popover controller

/*
 When setting the detail item, update the view and dismiss the popover controller if it's showing.
 */
- (void)setDetailItem:(id)newDetailItem {
    if (detailItem != newDetailItem) {
        [detailItem release];
        detailItem = [newDetailItem retain];
        
        // Update the view.
        navigationBar.topItem.title = [detailItem description];
    }
	
    if (popoverController != nil) {
        [popoverController dismissPopoverAnimated:YES];
    }        
}

#pragma mark -
#pragma mark Table View Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	if (server) {
		return 6;
	} else {
		// show No Servers View
		self.logoImageView.image = nil;
		self.backgroundImageView.image = nil;
		self.tableView.backgroundView = nil;
		noServersView.hidden = NO;
		[self.view bringSubviewToFront:self.noServersView];
		return 0;
	}
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kActionSection) {
		return 7;
	} else if (section == kNameSection) {
		if ([server shouldBePolled]) {
			return 4;
		} else {
			return 3;
		}
	} else if (section == kDetailsSection) {
		return 3;
	} else if (section == kPublicIPSection) {
		return [server.publicIpAddresses count];
	} else if (section == kPrivateIPSection) {
		return [server.privateIpAddresses count];
	} else if (section == kMetadataSection) {
		return [[server.metadata allKeys] count];
	} else {
		return 0;
	}
}

- (NSString *)tableView:(UITableView *)aTableView titleForHeaderInSection:(NSInteger)section {
	if (section == kNameSection) {
		return @"Overview";
	} else if (section == kDetailsSection) {
		return @"Technical Details";
	} else if (section == kPublicIPSection) {
		return @"Public IP Addresses";
	} else if (section == kPrivateIPSection) {
		return @"Private IP Addresses";
	} else if (section == kMetadataSection) {
		if ([[server.metadata allKeys] count] > 0) {
			return @"Server Metadata";
		} else {
			return @"";
		}
	}
	
	return @"Actions";
}

- (UITableViewCell *)tableView:(UITableView *)aTableView statusCellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"StatusCell";
	UITableViewCell *cell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier] autorelease];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	
	cell.textLabel.text = @"Status";
    cell.detailTextLabel.text = [server humanizedStatus];

    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)aTableView progressCellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"ProgressCell";
	UITableViewCell *cell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier] autorelease];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}
	
	cell.textLabel.text = @"Progress";
	
	if ([server shouldBePolled]) {
		if (progressView == nil) {
			progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
			CGRect r = progressView.frame;
			r.origin.x += 175;
			r.origin.y += 18;
			r.size.width += 230;
			progressView.frame = r;		
			[cell addSubview:progressView];
		}
		
		// looks weird when you animate the unknown status, since it has 100% progress
		if (![server.status isEqualToString:@"UNKNOWN"]) {
			[self animateProgressBarTo:[self.server humanizedProgress] * 0.01];
		}

		[self loadServer];
	}
	
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)aTableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	self.logoImageView.image = [ASICloudServersImage logoForImageId:server.imageId];
	self.backgroundImageView.image = [ASICloudServersImage backgroundForImageId:server.imageId];
	self.tableView.backgroundView = nil; // makes it clear
	self.detailItem = @"Server Details";
	self.navigationItem.title = @"Server Details";
	
	static NSString *CellIdentifier = @"Cell";
	UITableViewCell *cell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier] autorelease];
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

	UITableViewCell *actionCell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:@"ActionCell"];
	if (actionCell == nil) {
		actionCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ActionCell"] autorelease];
		//cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		actionCell.accessoryType = UITableViewCellAccessoryNone;
	}
	
	
	if (indexPath.section == kNameSection) {
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Server Name";
			cell.detailTextLabel.text = server.name;
		} else if (indexPath.row == 1) {
            return [self tableView:tableView statusCellForRowAtIndexPath:indexPath];
		} else if ((indexPath.row == 2) && [server shouldBePolled]) {
			return [self tableView:tableView progressCellForRowAtIndexPath:indexPath];
		} else { //if (indexPath.row == 2) {
			cell.textLabel.text = @"Host ID";
			cell.detailTextLabel.text = server.hostId;
		}
	} else if (indexPath.section == kDetailsSection) {
		ASICloudServersFlavor *flavor = [ASICloudServersFlavorRequest flavorForId:server.flavorId];
		if (indexPath.row == 0) {
			cell.textLabel.text = @"Operating System";			
			cell.detailTextLabel.text = [ASICloudServersImageRequest imageForId:server.imageId].name;
		} else if (indexPath.row == 1) {
			cell.textLabel.text = @"Memory";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%i MB", flavor.ram];
		} else if (indexPath.row == 2) {
			cell.textLabel.text = @"Disk";
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%i GB", flavor.disk];
		}
	} else if (indexPath.section == kActionSection) {
		if (indexPath.row == 0) {
			actionCell.textLabel.text = @"Reboot This Server";
		} else if (indexPath.row == 1) {
			actionCell.textLabel.text = @"Rename This Server";
		} else if (indexPath.row == 2) {
			actionCell.textLabel.text = @"Change the Size of RAM and Disk on This Server";
		} else if (indexPath.row == 3) {
			actionCell.textLabel.text = @"Change the Root Password";
		} else if (indexPath.row == 4) {
			actionCell.textLabel.text = @"Manage Backup Schedules";
		} else if (indexPath.row == 5) {
			actionCell.textLabel.text = @"Rebuild This Server"; // From Scratch" ?
		} else if (indexPath.row == 6) {
			actionCell.textLabel.text = @"Delete This Server";
		}
		return actionCell;
	} else if (indexPath.section == kPublicIPSection) {
		cell.textLabel.text = @"";
		cell.detailTextLabel.text = [[server publicIpAddresses] objectAtIndex:indexPath.row];
	} else if (indexPath.section == kPrivateIPSection) {
		cell.textLabel.text = @"";
		cell.detailTextLabel.text = [[server privateIpAddresses] objectAtIndex:indexPath.row];
	} else if (indexPath.section == kMetadataSection) {
		NSString *key = [[server.metadata allKeys] objectAtIndex:indexPath.row];
		cell.textLabel.text = key;
		cell.detailTextLabel.text = [server.metadata objectForKey:key];
	} else {
		cell.textLabel.text = @"";
		cell.detailTextLabel.text = @"";
	}
	
	return cell;
	
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {	
	if (indexPath.section == kActionSection) {
		
		NSString *className = nil;
		
		switch (indexPath.row) {
			case 0:
				className = @"RebootServerViewController";
				break;
			case 1:
				className = @"RenameServerViewController";
				break;
			case 2:
				className = @"ResizeServerViewController";
				break;
			case 3:
				className = @"ResetServerAdminPasswordViewController";
				break;
			case 4:
				className = @"ManageBackupSchedulesViewController";
				break;
			case 5:
				className = @"RebuildServerViewController";
				break;
			default:
				break;
		}

		if (className != nil) {
			// it's a modal view controller, so show it
			Class class = NSClassFromString(className);
			UIViewController *vc = [[class alloc] initWithNibName:className bundle:nil];
			vc.modalPresentationStyle = UIModalPresentationFormSheet;
			SEL method = NSSelectorFromString(@"setServerDetailViewController:");
			if ([vc respondsToSelector:method]) {
				[vc performSelector:method withObject:self];
			}
			
			[self presentModalViewController:vc animated:YES];
		} else {
			if (indexPath.row == 6) {
				NSString *title = @"Are you sure you want to delete this server?  This operation cannot be undone and you will lose all backup images.";
				//NSString *deleteTitle = [NSString stringWithFormat:@"Permanently Delete Server %@", self.server.name];
				NSString *deleteTitle = @"Delete This Server";
				UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:deleteTitle otherButtonTitles:nil];
				actionSheet.actionSheetStyle = UIActionSheetStyleBlackOpaque;
				//UITableViewCell *cell = [self tableView:self.tableView cellForRowAtIndexPath:indexPath];
				[actionSheet showInView:self.view];
				[actionSheet release];
			}			
		}
		
	} else if (indexPath.section == kPublicIPSection) {
		// TODO: popover with ping, copy, and email
		//ServersListViewController *vc = [[ServersListViewController alloc] initWithNibName:@"ServersListViewController" bundle:nil];
		MasterViewController *vc = [[MasterViewController alloc] init];
		UIPopoverController *pc = [[UIPopoverController alloc] initWithContentViewController:vc];
		//- (void)presentPopoverFromRect:(CGRect)rect inView:(UIView *)view permittedArrowDirections:(UIPopoverArrowDirection)arrowDirections animated:(BOOL)animated
		
		UITableViewCell *cell = [self tableView:self.tableView cellForRowAtIndexPath:indexPath];		
		[pc presentPopoverFromRect:cell.contentView.frame inView:self.tableView permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
		
		[pc release];
		[vc release];
		
	} else if (indexPath.section == kPrivateIPSection) {
	}
}

#pragma mark -
#pragma mark Action Sheet Delegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex	== 0) {
	    [self request:[ASICloudServersServerRequest deleteServerRequest:self.server.serverId] behavior:@"deleting your server" success:@selector(deleteServerSuccess:)];
	}
}



#pragma mark -
#pragma mark Button Handlers

-(void)addButtonPressed:(id)sender {
	AddServerViewController *vc = [[AddServerViewController alloc] initWithNibName:@"AddServerViewController" bundle:nil];
	vc.serverDetailViewController = self;
	vc.modalPresentationStyle = UIModalPresentationFormSheet;
	[self presentModalViewController:vc animated:YES];
}


#pragma mark -
#pragma mark Split view support

- (void)splitViewController: (UISplitViewController*)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem*)barButtonItem forPopoverController: (UIPopoverController*)pc {
    
    barButtonItem.title = @"Servers";
    [navigationBar.topItem setLeftBarButtonItem:barButtonItem animated:YES];
    self.popoverController = pc;
}


// Called when the view is shown again in the split view, invalidating the button and popover controller.
- (void)splitViewController: (UISplitViewController*)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem {
    
    [navigationBar.topItem setLeftBarButtonItem:nil animated:YES];
    self.popoverController = nil;
}


#pragma mark -
#pragma mark Rotation support

// Ensure that the view controller supports rotation and that the split view can therefore show in both portrait and landscape.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
	
	if (fromInterfaceOrientation == UIInterfaceOrientationPortrait || fromInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
		self.noServersImage.frame = CGRectMake(102, 37, 500, 500);
		self.noServersTitle.frame = CGRectMake(301, 567, 102, 22);
		self.noServersMessage.frame = CGRectMake(196, 623, 323, 21);
	} else { // UIInterfaceOrientationLandscapeLeft || UIInterfaceOrientationLandscapeRight	
		self.noServersImage.frame = CGRectMake(134, 180, 500, 500);
		self.noServersTitle.frame = CGRectMake(333, 710, 102, 22);
		self.noServersMessage.frame = CGRectMake(228, 766, 323, 21);
	}
}

#pragma mark -
#pragma mark View lifecycle

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
	[super viewDidLoad];
	if (self.interfaceOrientation == UIInterfaceOrientationPortrait || self.interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown) {
		// 704
		
		//self.noServersImage.frame = CGRectMake(102, 134, 500, 500);
	} else { // UIInterfaceOrientationLandscapeLeft || UIInterfaceOrientationLandscapeRight	
		self.noServersImage.frame = CGRectMake(102, 37, 500, 500);
		self.noServersTitle.frame = CGRectMake(301, 567, 102, 22);
		self.noServersMessage.frame = CGRectMake(196, 623, 323, 21);
		
	}
	
	progressTimer = nil;
	progressView = nil;
}


- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

/*
 - (void)viewDidAppear:(BOOL)animated {
 [super viewDidAppear:animated];
 }
 */
/*
 - (void)viewWillDisappear:(BOOL)animated {
 [super viewWillDisappear:animated];
 }
 */
/*
 - (void)viewDidDisappear:(BOOL)animated {
 [super viewDidDisappear:animated];
 }
 */

- (void)viewDidUnload {
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    self.popoverController = nil;
}


#pragma mark -
#pragma mark Memory management

/*
 - (void)didReceiveMemoryWarning {
 // Releases the view if it doesn't have a superview.
 [super didReceiveMemoryWarning];
 
 // Release any cached data, images, etc that aren't in use.
 }
 */

- (void)dealloc {
    [popoverController release];
    [navigationBar release];
    
    [detailItem release];
	
	[tableView release];
	[server release];
	
	[logoImageView release];
	[backgroundImageView release];
	
	[noServersView release];
	[noServersImage release];
	[noServersTitle release];
	[noServersMessage release];
	
	[serversListViewController release];
	
	if (progressView != nil) {
		[progressView release];
	}
	
    [super dealloc];
}

@end
