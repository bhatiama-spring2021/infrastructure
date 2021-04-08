exports.handler = (event, context, callback) => {
    console.log('Hello world!');
    callback(null, 'It works!');
}