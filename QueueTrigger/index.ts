import { AzureFunction, Context } from "@azure/functions"
import * as _ from "lodash";

// Change queueName and connection in function.json

// Sample Queue Message:
//     123
// This will make the beaver works for 123 seconds

function testBench(busySeconds: number, min: number = 0, max: number = 999, select: number = 3): number[] {
    let queue: number[] = _.range(min, max);
    const startTime: number = Date.now();
    while (Date.now() - startTime < busySeconds * 1000) {
        const srcNumber: number = _.random(0, queue.length - 1);
        const destNumber: number = _.random(0, queue.length - 1);
        let temp: number = queue[srcNumber];
        queue[srcNumber] = queue[destNumber];
        queue[destNumber] = temp;
    }
    return _.slice(queue, 0, select);
}

const queueTrigger: AzureFunction = async function (context: Context, myQueueItem: string): Promise<void> {
    const { functionName, invocationId } = context.executionContext;

    let busySeconds = Number(myQueueItem);
    if (isNaN(busySeconds)) {
        // Try base64 decoding
        try {
            const nonBase64 = atob(myQueueItem);
            busySeconds = Number(nonBase64);
        } catch {}
    }
    if (isNaN(busySeconds)) {
        context.log(`Busy Beaver ${functionName} failes to process queue ${invocationId}, message cannot be parsed ${myQueueItem}`);
        return;
    }

    context.log(`Busy Beaver ${functionName} receives queue ${invocationId}, ready to work for ${busySeconds} seconds`);
    const startTime: string = new Date().toISOString();
    const result = String(testBench(busySeconds));
    const endTime: string = new Date().toISOString();
    context.log(`Busy Beaver ${functionName} finishes queue ${invocationId}, random_numbers: ${result}, start_time: ${startTime}, end_time: ${endTime}`);
};

export default queueTrigger;
