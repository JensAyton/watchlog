#import <Foundation/Foundation.h>
#include <asl.h>
#include <notify.h>
#include <notify_keys.h>
#include <sys/time.h>


static void ConfigureQuery(aslmsg query)
{
	const char param[] = "5";	// ASL_LEVEL_NOTICE
	
	asl_set_query(query, ASL_KEY_LEVEL, param, ASL_QUERY_OP_LESS_EQUAL | ASL_QUERY_OP_NUMERIC);
}

static void MessageRecieved(aslmsg msg)
{
	const char *sender = asl_get(msg, ASL_KEY_SENDER);
	const char *message = asl_get(msg, ASL_KEY_MSG);
	printf("%s: %s\n", sender, message);
}


int main(int argc, const char * argv[])
{
	@autoreleasepool
	{
		/*
			We use ASL_KEY_MSG_ID to see each message once, but there's no
			obvious way to get the "next" ID. To bootstrap the process, we'll
			search by timestamp until we've seen a message.
		*/
		
		struct timeval timeval = { .tv_sec = 0 };
		gettimeofday(&timeval, NULL);
		unsigned long long startTime = timeval.tv_sec;
		__block unsigned long long lastSeenID = 0;
		
		/*
			syslogd posts kNotifyASLDBUpdate (com.apple.system.logger.message)
			through the notify API when it saves messages to the ASL database.
			There is some coalescing - currently it is sent at most twice per
			second - but there is no documented guarantee about this. In any
			case, there may be multiple messages per notification.
			
			Notify notifications don't carry any payload, so we need to search
			for the messages.
		*/
		int notifyToken;	// Can be used to unregister with notify_cancel().
		notify_register_dispatch(kNotifyASLDBUpdate, &notifyToken, dispatch_get_main_queue(), ^(int token) {
			// At least one message has been posted; build a search query.
			@autoreleasepool
			{
				aslmsg query = asl_new(ASL_TYPE_QUERY);
				char stringValue[64];
				if (lastSeenID > 0)
				{
					snprintf(stringValue, sizeof stringValue, "%llu", lastSeenID);
					asl_set_query(query, ASL_KEY_MSG_ID, stringValue, ASL_QUERY_OP_GREATER | ASL_QUERY_OP_NUMERIC);
				}
				else
				{
					snprintf(stringValue, sizeof stringValue, "%llu", startTime);
					asl_set_query(query, ASL_KEY_TIME, stringValue, ASL_QUERY_OP_GREATER_EQUAL | ASL_QUERY_OP_NUMERIC);
				}
				ConfigureQuery(query);
				
				// Iterate over new messages.
				aslmsg msg;
				aslresponse response = asl_search(NULL, query);
				while ((msg = aslresponse_next(response)))
				{
					// Do stuff.
					MessageRecieved(msg);
					
					// Keep track of which messages we've seen.
					lastSeenID = atoll(asl_get(msg, ASL_KEY_MSG_ID));
				}
				aslresponse_free(response);
			}
		});
		
		// Run forever.
		dispatch_main();
	}
}

