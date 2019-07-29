import { AzureFunction, Context, HttpRequest } from "@azure/functions";
import * as _ from "lodash";

// Sample Request: https://functionapp.azurewebsites.net/api/HttpTrigger?busySeconds=3

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

const httpTrigger: AzureFunction = async function (context: Context, req: HttpRequest): Promise<void> {
    const { functionName, invocationId } = context.executionContext;
    const busySeconds = (req.query.busySeconds || (req.body && req.body.busySeconds));

    if (!busySeconds) {
        context.res = {
            status: 400,
            body: "Needs to define ?busySeconds= to set beaver to work!"
        }
        return;
    }

    context.log(`Busy Beaver ${functionName} receives http ${invocationId}, ready to work for ${busySeconds} seconds`);
    const startTime: string = new Date().toISOString();
    const result = String(testBench(busySeconds));
    const endTime: string = new Date().toISOString();

    context.res = {
        status: 200,
        mimetype: "application/json",
        body: `{
            "start_time": "${startTime}",
            "end_time": "${endTime}",
            "function_name": "${functionName}",
            "invocation_id": "${invocationId}",
            "random_numbers": [${result}]
        }`
    }

    context.log(`Busy Beaver ${functionName} finishes http ${invocationId}, random_numbers: ${result}, start_time: ${startTime}, end_time: ${endTime}`);
};

export default httpTrigger;
