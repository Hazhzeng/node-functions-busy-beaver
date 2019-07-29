import { AzureFunction, Context } from "@azure/functions"
import * as _ from "lodash";

// Change BUSY_SECONDS and function.json cron expression

const BUSY_SECONDS = 1;

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

const timerTrigger: AzureFunction = async function (context: Context, myTimer: any): Promise<void> {
    const { functionName, invocationId } = context.executionContext;
    context.log(`Busy Beaver ${functionName} receives timer ${invocationId}, ready to work for ${BUSY_SECONDS} seconds`);

    if (myTimer.IsPastDue)
    {
        context.log(`Busy Beaver ${functionName} passed due on ${invocationId}`);
    }

    const startTime: string = new Date().toISOString();
    const result = String(testBench(BUSY_SECONDS));
    const endTime: string = new Date().toISOString();

    context.log(`Busy Beaver ${functionName} finishes timer ${invocationId}, random_numbers: ${result}, start_time: ${startTime}, end_time: ${endTime}`);
};

export default timerTrigger;
