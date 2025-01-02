FROM public.ecr.aws/lambda/python:3.12

ENV HOME=/tmp

WORKDIR /var/task

COPY requirements.txt ./
RUN pip install -r requirements.txt

COPY . ./

CMD [ "lambda_function.handler" ]
