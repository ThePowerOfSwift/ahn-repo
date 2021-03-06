#!/usr/bin/env python

# /********************************************************************
# Filename: train.py
# Author: AHN
# Creation Date: Aug 26, 2017
# **********************************************************************/
#
# Build and train countbits model
#

from __future__ import division, print_function
from pdb import set_trace as BP
import inspect
import os,sys,re,json
import numpy as np
from numpy.random import random
import argparse
import keras.layers as kl
import keras.models as km
import keras.optimizers as kopt

# Look for modules in our pylib folder
SCRIPTPATH = os.path.dirname(os.path.realpath(__file__))
sys.path.append(re.sub(r'/proj/.*',r'/pylib', SCRIPTPATH))
import ahnutil as ut


BATCH_SIZE=1000

#---------------------------
def usage(printmsg=False):
    name = os.path.basename(__file__)
    msg = '''
    Name:
      %s --  Build and train countbits model
    Synopsis:
      %s --nbits <n> --epochs <n> --ntrain <n> ---nval <n> --rate <learning_rate>
    Description:
      Train a model to count how many of the nbits input bits are set
    Example:
      %s --nbits 20 --epochs 1000 --ntrain 10000 --nval 1000 --rate 0.001
    ''' % (name,name,name)
    if printmsg:
        print(msg)
        exit(1)
    else:
        return msg

#-------------------------------------
def generate_inp_outp(nsamp, nbits):
    nset = np.random.randint(0,nbits+1,nsamp)
    inp = np.array([[1]*n + [0]*(nbits-n) for n in nset])
    for x in inp: np.random.shuffle(x)
    outp = nset
    #BP()
    return inp,outp

class CountModel:
    #---------------------------------
    def __init__(self,nbits,rate=0):
        self.nbits = nbits
        self.rate = rate
        self.build_model()

    #-----------------------
    def build_model(self):
        inputs = kl.Input(shape=(self.nbits,))
        #output = kl.Dense(1, name='dense0')(inputs)
        output = kl.Dense(1, activation='relu', name='dense0')(inputs)
        #x = kl.BatchNormalization()(x)
        #x = kl.Dense(10, activation='relu', name='dense1')(x)
        #x = kl.Dense(10, activation='relu', name='dense2')(x)
        #x = kl.Dense(10, activation='relu', name='dense3')(x)
        #x = kl.BatchNormalization()(x)
        #x = kl.Dropout(0.5)(x)
        #x = kl.Dense(10, activation='relu', name='dense1')(x)
        #x = kl.BatchNormalization()(x)
        #x = kl.Dropout(0.5)(x)
        #x = kl.Dense(10, activation='relu', name='dense2')(x)
        #x = kl.BatchNormalization()(x)
        #x = kl.Dense(10, activation='relu', name='dense3')(x)
        #x = kl.BatchNormalization()(x)
        #x = kl.Dense(10, activation='relu', name='dense4')(x)
        #x = kl.BatchNormalization()(x)
        #output = kl.Dense(self.maxint+1, activation='softmax', name='out' )(x)
        self.model = km.Model(inputs=inputs, outputs=output)
        self.model.summary()
        if self.rate > 0:
            opt = kopt.Adam(self.rate)
            #opt = kopt.SGD(self.rate)
        else:
            opt = kopt.Adam()
            #opt = kopt.SGD()
        self.model.compile(loss='mean_squared_error', optimizer=opt, metrics=['accuracy'])

#-----------
def main():
    if len(sys.argv) == 1:
        usage(True)

    parser = argparse.ArgumentParser(usage=usage())
    parser.add_argument("--nbits", required=True, type=int)
    parser.add_argument("--epochs", required=True, type=int)
    parser.add_argument("--ntrain", required=True, type=int)
    parser.add_argument("--nval",   required=True, type=int)
    parser.add_argument("--rate",   required=False, default=0, type=float)
    args = parser.parse_args()
    model = CountModel(args.nbits, args.rate)
    traindata, trainout = generate_inp_outp(args.ntrain, args.nbits)
    #BP()
    valdata, valout     = generate_inp_outp(args.nval, args.nbits)
    valdata_orig = valdata.copy()
    # Normalize training and validation data by train data mean and std
    mean = traindata.mean()
    std =  traindata.std()
    traindata = (traindata - mean) / std
    valdata = (valdata - mean) / std

    if os.path.exists('model.h5'): model.model.load_weights('model.h5')
    model.model.fit(traindata, trainout,
                    batch_size=BATCH_SIZE, epochs=args.epochs,
                    validation_data=(valdata, valout))
    model.model.save_weights('model.h5')
    # print('>>>>>iter %d' % i)
    # for idx,layer in enumerate(model.model.layers):
    #     weights = layer.get_weights() # list of numpy arrays
    #     print('Weights for layer %d:',idx)
    #     print(weights)
    #model.model.fit(images['train_data'], meta['train_classes'],
    #                batch_size=BATCH_SIZE, epochs=args.epochs)
    #model.model.save('dump1.hd5')
    preds = model.model.predict(valdata, batch_size=BATCH_SIZE)
    for x in zip(valdata_orig,preds):
        print(x)

if __name__ == '__main__':
    main()
